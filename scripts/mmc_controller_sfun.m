function mmc_controller_sfun(block)
%MMC_CONTROLLER_SFUN Discrete NLM, balancing, dead-time, and energy control.
% Dialog parameter: 1 = HB-MMC, 2 = FB-MMC.

setup(block);
end

function setup(block)
block.NumDialogPrms = 2; % topology_id, Vphase_cmd
block.NumInputPorts = 3;
block.NumOutputPorts = 12;

block.InputPort(1).Dimensions = 6;   % [Au Al Bu Bl Cu Cl] arm currents
block.InputPort(2).Dimensions = 60;  % ten capacitor voltages per arm
block.InputPort(3).Dimensions = 3;   % measured load phase-to-neutral voltages
for idx = 1:3
    block.InputPort(idx).DatatypeID = 0;
    block.InputPort(idx).Complexity = 'Real';
    % Outputs come only from DWork; measured values are consumed in Update.
    % This one-sample delay breaks the physical-network/controller loop.
    block.InputPort(idx).DirectFeedthrough = false;
end

dims = [60 60 60 60 3 3 6 6 60 6 6 6];
for idx = 1:block.NumOutputPorts
    block.OutputPort(idx).Dimensions = dims(idx);
    block.OutputPort(idx).DatatypeID = 0;
    block.OutputPort(idx).Complexity = 'Real';
end

Ts = evalin('base', 'Ts_elec');
block.SampleTimes = [Ts 0];
block.SimStateCompliance = 'DefaultSimState';

block.RegBlockMethod('PostPropagationSetup', @doPostPropSetup);
block.RegBlockMethod('InitializeConditions', @initializeConditions);
block.RegBlockMethod('Outputs', @outputs);
block.RegBlockMethod('Update', @update);
end

function doPostPropSetup(block)
names = {'state','pending','dead','int_energy','int_circ','rotation', ...
    'tick','v_cmd','v_limited','arm_ref','arm_quant','k_insert', ...
    'amp_est','int_voltage'};
widths = [60 60 60 3 3 6 1 3 3 6 6 6 1 1];
block.NumDworks = numel(names);
for idx = 1:numel(names)
    block.Dwork(idx).Name = names{idx};
    block.Dwork(idx).Dimensions = widths(idx);
    block.Dwork(idx).DatatypeID = 0;
    block.Dwork(idx).Complexity = 'Real';
    block.Dwork(idx).UsedAsDiscState = true;
end
end

function initializeConditions(block)
for idx = 1:block.NumDworks
    block.Dwork(idx).Data = zeros(block.Dwork(idx).Dimensions, 1);
end
end

function outputs(block)
topology = block.DialogPrm(1).Data;
state = block.Dwork(1).Data;
pending = block.Dwork(2).Data;
dead = block.Dwork(3).Data;
activeState = state;
activeState(dead > 0) = 0;

g1 = zeros(60,1); g2 = g1; g3 = g1; g4 = g1;
gateOn = 15; % V, explicit gate drive above the IGBT threshold
if topology == 1
    % HB: bypass [1 0], positive insertion [0 1], dead time [0 0].
    g1(activeState == 0 & dead == 0) = gateOn;
    g2(activeState == 1 & dead == 0) = gateOn;
else
    % FB order: upper-left, lower-left, upper-right, lower-right.
    % +Vc [1 0 0 1], bypass [0 1 0 1], -Vc [0 1 1 0].
    normal = dead == 0;
    bypass = activeState == 0 & normal;
    positive = activeState == 1 & normal;
    negative = activeState == -1 & normal;
    g1(positive) = gateOn; g4(positive) = gateOn;
    g2(bypass) = gateOn; g4(bypass) = gateOn;
    g2(negative) = gateOn; g3(negative) = gateOn;

    % During an FB state transition, retain a device that is common to the
    % old and new safe states. Only the commutating complementary leg is
    % placed in dead time. Positive<->negative has no common device and
    % therefore still uses a full all-off interval.
    transition = dead > 0;
    leftLowerCommon = transition & (state <= 0) & (pending <= 0);
    rightLowerCommon = transition & (state >= 0) & (pending >= 0);
    g2(leftLowerCommon) = gateOn;
    g4(rightLowerCommon) = gateOn;
end

block.OutputPort(1).Data = g1;
block.OutputPort(2).Data = g2;
block.OutputPort(3).Data = g3;
block.OutputPort(4).Data = g4;
block.OutputPort(5).Data = block.Dwork(8).Data;
block.OutputPort(6).Data = block.Dwork(9).Data;
block.OutputPort(7).Data = block.Dwork(10).Data;
block.OutputPort(8).Data = block.Dwork(11).Data;
block.OutputPort(9).Data = activeState;
block.OutputPort(10).Data = block.Dwork(12).Data;

statesByArm = reshape(activeState, 10, 6);
block.OutputPort(11).Data = sum(statesByArm > 0, 1).';
block.OutputPort(12).Data = sum(statesByArm < 0, 1).';
end

function update(block)
Ts = evalin('base', 'Ts_elec');
TsMod = evalin('base', 'Ts_mod');
deadTime = evalin('base', 'dead_time');
modRatio = max(1, round(TsMod / Ts));
deadSteps = max(1, round(deadTime / Ts));

state = block.Dwork(1).Data;
pending = block.Dwork(2).Data;
dead = block.Dwork(3).Data;
for idx = 1:60
    if dead(idx) > 0
        dead(idx) = dead(idx) - 1;
        if dead(idx) <= 0
            state(idx) = pending(idx);
        end
    end
end

tick = block.Dwork(7).Data + 1;
if mod(tick - 1, modRatio) == 0
    topology = block.DialogPrm(1).Data;
    Vdc = evalin('base', 'Vdc');
    VcRef = evalin('base', 'Vc_ref');
    VarmRated = evalin('base', 'Varm_rated');
    f1 = evalin('base', 'f1');
    commandPeak = block.DialogPrm(2).Data;
    rampStart = evalin('base', 'ramp_start');
    rampTime = evalin('base', 'ramp_time');
    Rload = evalin('base', 'Rload');
    Lload = evalin('base', 'Lload');
    KpEnergy = evalin('base', 'Kp_energy');
    KiEnergy = evalin('base', 'Ki_energy');
    energyCurrentLimit = evalin('base', 'energy_current_limit');
    circCurrentMin = evalin('base', 'circ_current_min');
    circCurrentMax = evalin('base', 'circ_current_max');
    KpCirc = evalin('base', 'Kp_circ');
    KiCirc = evalin('base', 'Ki_circ');
    commonVoltageLimit = evalin('base', 'common_voltage_limit');
    armBalanceGain = evalin('base', 'arm_balance_gain');
    armBalanceLimitPu = evalin('base', 'arm_balance_limit_pu');
    sortHysteresisPu = evalin('base', 'sort_hysteresis_pu');
    voltageAmpTau = evalin('base', 'voltage_amp_tau');
    KpVoltage = evalin('base', 'Kp_voltage');
    KiVoltage = evalin('base', 'Ki_voltage');
    voltageControlDelay = evalin('base', 'voltage_control_delay');
    voltageCorrectionLimit = evalin('base', 'voltage_correction_limit');

    time = block.CurrentTime;
    ramp = min(max((time-rampStart)/rampTime, 0), 1);
    angles = 2*pi*f1*time + [0; -2*pi/3; 2*pi/3];
    vCommand = commandPeak*ramp*sin(angles);
    if topology == 1
        vLimited = min(max(vCommand, -Vdc/2), Vdc/2);
    else
        vLimited = vCommand;
    end

    % Three-phase synchronous detection rejects the balanced 100 Hz term:
    % (2/3)*sum(v_phase.*sin(theta)) is the in-phase fundamental amplitude.
    measuredPhaseVoltage = block.InputPort(3).Data;
    synchronousAmplitude = (2/3)*sum(measuredPhaseVoltage.*sin(angles));
    amplitudeEstimate = block.Dwork(13).Data;
    amplitudeEstimate = amplitudeEstimate + ...
        min(TsMod/voltageAmpTau,1)*(synchronousAmplitude-amplitudeEstimate);
    voltageIntegral = block.Dwork(14).Data;
    vControl = vLimited;
    effectivePeak = min(commandPeak,Vdc/2)*ramp;
    if topology == 2
        targetPeak = commandPeak*ramp;
        voltageCorrection = 0;
        if time >= rampStart+rampTime+voltageControlDelay
            voltageError = targetPeak-amplitudeEstimate;
            trialVoltageIntegral = voltageIntegral+voltageError*TsMod;
            unconstrainedCorrection = KpVoltage*voltageError + ...
                KiVoltage*trialVoltageIntegral;
            voltageCorrection = min(max(unconstrainedCorrection, ...
                -voltageCorrectionLimit),voltageCorrectionLimit);
            if unconstrainedCorrection == voltageCorrection
                voltageIntegral = trialVoltageIntegral;
            end
        end
        maximumPhasePeak = max(VarmRated-Vdc/2,0);
        effectivePeak = min(max(targetPeak+voltageCorrection,0), ...
            maximumPhasePeak);
        vControl = effectivePeak*sin(angles);
    end

    iArm = block.InputPort(1).Data;
    vCaps = reshape(block.InputPort(2).Data, 10, 6);
    meanVc = mean(vCaps, 1).';
    intEnergy = block.Dwork(4).Data;
    intCirc = block.Dwork(5).Data;
    rotation = block.Dwork(6).Data;
    armRef = zeros(6,1);

    fullPeak = effectivePeak;
    zLoad2 = Rload^2 + (2*pi*f1*Lload)^2;
    phasePower = 0.5*fullPeak^2*Rload/zLoad2;
    iCircFeedforward = phasePower/Vdc;

    for phase = 1:3
        upper = 2*phase-1;
        lower = upper+1;
        energyError = VcRef - 0.5*(meanVc(upper)+meanVc(lower));
        trialEnergy = intEnergy(phase) + energyError*TsMod;
        energyCorrection = KpEnergy*energyError + KiEnergy*trialEnergy;
        energyCorrectionSat = min(max(energyCorrection, ...
            -energyCurrentLimit), energyCurrentLimit);
        if energyCorrection == energyCorrectionSat
            intEnergy(phase) = trialEnergy;
        end
        iCircRef = min(max(iCircFeedforward + energyCorrectionSat, ...
            circCurrentMin), circCurrentMax);
        iCirc = 0.5*(iArm(upper)+iArm(lower));
        circError = iCirc-iCircRef;
        trialCirc = intCirc(phase) + circError*TsMod;
        commonVoltage = KpCirc*circError + KiCirc*trialCirc;
        commonVoltageSat = min(max(commonVoltage, ...
            -commonVoltageLimit), commonVoltageLimit);
        if commonVoltage == commonVoltageSat
            intCirc(phase) = trialCirc;
        end

        armImbalance = meanVc(upper)-meanVc(lower);
        balanceVoltageLimit = armBalanceLimitPu*VcRef;
        balanceVoltage = min(max(armBalanceGain*armImbalance, ...
            -balanceVoltageLimit), balanceVoltageLimit);
        armRef(upper) = Vdc/2-vControl(phase)+commonVoltageSat+balanceVoltage;
        armRef(lower) = Vdc/2+vControl(phase)+commonVoltageSat-balanceVoltage;
    end

    if topology == 1
        armRef = min(max(armRef, 0), VarmRated);
    else
        armRef = min(max(armRef, -VarmRated), VarmRated);
    end

    desired = zeros(60,1);
    kInsert = zeros(6,1);
    armQuant = zeros(6,1);
    for arm = 1:6
        vcForNlm = max(meanVc(arm), 1);
        k = round(armRef(arm)/vcForNlm);
        if topology == 1
            k = min(max(k,0),10);
        else
            k = min(max(k,-10),10);
        end
        kInsert(arm) = k;
        armQuant(arm) = k*vcForNlm;
        count = abs(k);
        if count > 0
            coefficient = sign(k);
            if topology == 1
                coefficient = 1;
            end
            base = (arm-1)*10;
            present = find(state(base+(1:10)) == coefficient);
            balancedAndHeld = numel(present) == count && ...
                (max(vCaps(:,arm))-min(vCaps(:,arm))) < ...
                sortHysteresisPu*VcRef;
            if balancedAndHeld
                % Minimum holding time: do not open a series arm merely to
                % rotate tied cells when they are already balanced.
                selected = present;
            else
                capCurrentSign = coefficient*iArm(arm);
                tie = mod((0:9).'-rotation(arm),10)*1e-8;
                if capCurrentSign > 1e-6
                    metric = vCaps(:,arm)+tie;  % charge the lowest cells
                elseif capCurrentSign < -1e-6
                    metric = -vCaps(:,arm)+tie; % discharge the highest cells
                else
                    metric = tie;               % rotating tie break
                end
                [~,order] = sort(metric,'ascend');
                selected = order(1:count);
                rotation(arm) = mod(rotation(arm)+1,10);
            end
            desired(base+selected) = coefficient;
        end
    end

    for idx = 1:60
        if desired(idx) ~= state(idx)
            pending(idx) = desired(idx);
            dead(idx) = deadSteps;
        end
    end

    block.Dwork(4).Data = intEnergy;
    block.Dwork(5).Data = intCirc;
    block.Dwork(6).Data = rotation;
    block.Dwork(8).Data = vCommand;
    block.Dwork(9).Data = vLimited;
    block.Dwork(10).Data = armRef;
    block.Dwork(11).Data = armQuant;
    block.Dwork(12).Data = kInsert;
    block.Dwork(13).Data = amplitudeEstimate;
    block.Dwork(14).Data = voltageIntegral;
end

block.Dwork(1).Data = state;
block.Dwork(2).Data = pending;
block.Dwork(3).Data = dead;
block.Dwork(7).Data = tick;
end
