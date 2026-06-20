% VERIFY_MMC_SCALED End-to-end checks for the scaled 10 kV comparison.
run(fullfile(fileparts(mfilename('fullpath')),'init_mmc_comparison.m'));

requiredCases = {'HB_4kV','HB_5kV','HB_7kV','FB_4kV','FB_5kV','FB_7kV'};
for caseIndex = 1:numel(requiredCases)
    assert(isfile(fullfile(project_root,'results',[requiredCases{caseIndex} '.mat'])), ...
        'Missing result for %s.',requiredCases{caseIndex});
end

fbLoaded = load(fullfile(project_root,'results','FB_7kV.mat'),'caseData');
hbLoaded = load(fullfile(project_root,'results','HB_7kV.mat'),'caseData');
fb = fbLoaded.caseData;
hb = hbLoaded.caseData;
assert(strcmp(fb.meta.model_revision,model_revision) && ...
    strcmp(hb.meta.model_revision,model_revision),'Verification result revision mismatch.');

fbSteady = fb.v_phase_actual.time >= fb.meta.Tstop-fb.meta.analysis_window;
hbSteady = hb.v_phase_actual.time >= hb.meta.Tstop-hb.meta.analysis_window;
fbTime = fb.v_phase_actual.time(fbSteady);
hbTime = hb.v_phase_actual.time(hbSteady);

fbStates = reshape(fb.sm_switching_states.data(fbSteady,:),[],N,6);
fbCaps = reshape(fb.v_capacitors.data(fbSteady,:),[],N,6);
fbStateArmVoltage = squeeze(sum(fbStates.*fbCaps,2));
fbNegativeCount = fb.negative_count.data(fbSteady,:);
fbArmReference = fb.arm_voltage_reference.data(fbSteady,:);

verification = struct;
verification.model_revision = model_revision;
verification.fb_command_peak_kV = fb.meta.command_peak/1e3;
verification.fb_fundamental_peak_kV = mean(fundamentalPeaks( ...
    fbTime,fb.v_phase_actual.data(fbSteady,:),f1))/1e3;
verification.fb_tracking_error_percent = 100*( ...
    verification.fb_fundamental_peak_kV-7)/7;
verification.fb_minimum_arm_reference_kV = min(fbArmReference,[],'all')/1e3;
verification.fb_maximum_arm_reference_kV = max(fbArmReference,[],'all')/1e3;
verification.fb_negative_count_max = max(fbNegativeCount,[],'all');
verification.fb_positive_count_max = max(fb.positive_count.data(fbSteady,:),[],'all');
verification.fb_negative_state_samples = nnz(fbStates < 0);
verification.fb_state_arm_voltage_min_kV = min(fbStateArmVoltage,[],'all')/1e3;
verification.fb_state_arm_voltage_max_kV = max(fbStateArmVoltage,[],'all')/1e3;
verification.fb_capacitor_min_kV = min(fbCaps,[],'all')/1e3;
verification.fb_capacitor_max_kV = max(fbCaps,[],'all')/1e3;
verification.fb_capacitor_mean_kV = mean(fbCaps,'all')/1e3;
fbMeanTrace = mean(reshape(fbCaps,[],60),2);
verification.fb_capacitor_mean_start_kV = fbMeanTrace(1)/1e3;
verification.fb_capacitor_mean_end_kV = fbMeanTrace(end)/1e3;
verification.fb_capacitor_spread_max_V = max( ...
    max(fbCaps,[],2)-min(fbCaps,[],2),[],'all');
fbTrend = polyfit(fbTime,fbMeanTrace,1);
verification.fb_capacitor_slope_V_per_s = fbTrend(1);

fbArmCurrent = fb.i_arm.data(fbSteady,:);
fbCirc = 0.5*[fbArmCurrent(:,1)+fbArmCurrent(:,2), ...
    fbArmCurrent(:,3)+fbArmCurrent(:,4), ...
    fbArmCurrent(:,5)+fbArmCurrent(:,6)];
verification.fb_arm_current_peak_A = max(abs(fbArmCurrent),[],'all');
verification.fb_circulating_current_peak_A = max(abs(fbCirc),[],'all');

hbLimited = hb.v_phase_limited.data(hbSteady,:);
hbArmReference = hb.arm_voltage_reference.data(hbSteady,:);
verification.hb_limited_phase_peak_kV = max(abs(hbLimited),[],'all')/1e3;
verification.hb_fundamental_peak_kV = mean(fundamentalPeaks( ...
    hbTime,hb.v_phase_actual.data(hbSteady,:),f1))/1e3;
verification.hb_arm_reference_min_kV = min(hbArmReference,[],'all')/1e3;
verification.hb_arm_reference_max_kV = max(hbArmReference,[],'all')/1e3;
verification.hb_negative_count_max = max(hb.negative_count.data,[],'all');

% Validate the implemented capacitor-current convention from full-model data.
dt = mean(diff(fbTime));
fbCapCurrentMeasured = Csm_FB*diff(fbCaps,1,1)/dt;
predictedCapCurrent = fbStates(1:end-1,:,:).* ...
    reshape(fbArmCurrent(1:end-1,:),[],1,6);
unchangedState = fbStates(2:end,:,:) == fbStates(1:end-1,:,:);
active = unchangedState & abs(predictedCapCurrent) > 20;
agreement = sign(fbCapCurrentMeasured(active)) == sign(predictedCapCurrent(active));
verification.capacitor_current_sign_agreement = mean(agreement);

% Independent deterministic Sort-and-Select check at the 1.5 kV scale.
candidateVoltages = [1470 1520 1490 1540 1500 1480 1530 1510 1460 1550].';
[~,lowOrder] = sort(candidateVoltages,'ascend');
[~,highOrder] = sort(candidateVoltages,'descend');
verification.charge_selected = sort(lowOrder(1:3)).';
verification.discharge_selected = sort(highOrder(1:3)).';

assert(verification.fb_command_peak_kV == 7,'FB verification is not the 7 kV case.');
assert(abs(verification.fb_tracking_error_percent) <= 5, ...
    'FB 7 kV fundamental is outside the +/-5%% target.');
assert(verification.fb_minimum_arm_reference_kV < -1.5 && ...
    verification.fb_maximum_arm_reference_kV > 11.5 && ...
    verification.fb_maximum_arm_reference_kV <= 15, ...
    'FB arm references do not demonstrate the required negative/+12 kV range.');
assert(verification.fb_negative_count_max >= 1 && ...
    verification.fb_negative_state_samples > 0, ...
    'FB 7 kV case contains no actual negative insertion state.');
assert(verification.fb_state_arm_voltage_min_kV < -1.0, ...
    'FB switching states and measured capacitors do not produce negative arm voltage.');
assert(verification.fb_positive_count_max >= 7 && ...
    verification.fb_state_arm_voltage_max_kV > 10, ...
    'FB switching states do not demonstrate positive insertion polarity.');
assert(verification.fb_capacitor_min_kV > 1.35 && ...
    verification.fb_capacitor_max_kV < 1.65, ...
    'FB capacitor voltages are not bounded around 1.5 kV.');
assert(abs(verification.fb_capacitor_mean_end_kV-1.5) < 0.03 && ...
    abs(verification.fb_capacitor_mean_end_kV-1.5) < ...
    abs(verification.fb_capacitor_mean_start_kV-1.5), ...
    'FB capacitor energy is not converging toward the 1.5 kV reference.');
assert(verification.fb_arm_current_peak_A < 1e3 && ...
    verification.fb_circulating_current_peak_A < 500, ...
    'FB arm or circulating current is not bounded.');
assert(verification.capacitor_current_sign_agreement > 0.75, ...
    'Logged data do not confirm i_cap = state*i_arm.');
assert(verification.hb_limited_phase_peak_kV <= 5+1e-9 && ...
    verification.hb_fundamental_peak_kV < 6.5, ...
    'HB 7 kV request was not visibly limited by the conventional boundary.');
assert(verification.hb_arm_reference_min_kV >= -1e-9 && ...
    verification.hb_arm_reference_max_kV <= 10+1e-9 && ...
    verification.hb_negative_count_max == 0, ...
    'HB model exceeded its 0...10 kV arm range or used negative insertion.');
assert(isequal(verification.charge_selected,[1 6 9]) && ...
    isequal(verification.discharge_selected,[4 7 10]), ...
    'Sort-and-Select ordering is incorrect.');
assert(N*1e3 < Vdc/2+7e3 && Varm_rated_FB >= Vdc/2+7e3, ...
    'Installed-arm-voltage capability diagnostic is inconsistent.');

for caseIndex = 1:numel(requiredCases)
    loaded = load(fullfile(project_root,'results',[requiredCases{caseIndex} '.mat']),'caseData');
    data = loaded.caseData;
    assert(all(isfinite([data.v_phase_actual.data(:);data.i_load.data(:); ...
        data.v_capacitors.data(:);data.i_arm.data(:);data.i_dc.data(:)])), ...
        '%s contains NaN or Inf.',requiredCases{caseIndex});
end

save(fullfile(project_root,'results','submodule_verification.mat'),'verification');
fid = fopen(fullfile(project_root,'results','submodule_verification.txt'),'w');
fprintf(fid,'Scaled 10 kV MMC end-to-end verification: PASS\n');
fprintf(fid,'FB fundamental: %.6f kVpk (error %+.3f%%)\n', ...
    verification.fb_fundamental_peak_kV,verification.fb_tracking_error_percent);
fprintf(fid,'FB arm-reference range: %.6f to %.6f kV\n', ...
    verification.fb_minimum_arm_reference_kV,verification.fb_maximum_arm_reference_kV);
fprintf(fid,'FB negative count/state samples: %.0f / %d\n', ...
    verification.fb_negative_count_max,verification.fb_negative_state_samples);
fprintf(fid,'FB minimum state-derived arm voltage: %.6f kV\n', ...
    verification.fb_state_arm_voltage_min_kV);
fprintf(fid,'FB capacitor range/mean: %.6f to %.6f / %.6f kV\n', ...
    verification.fb_capacitor_min_kV,verification.fb_capacitor_max_kV, ...
    verification.fb_capacitor_mean_kV);
fprintf(fid,'FB capacitor mean start/end: %.6f / %.6f kV\n', ...
    verification.fb_capacitor_mean_start_kV, ...
    verification.fb_capacitor_mean_end_kV);
fprintf(fid,'FB capacitor mean slope: %+.6f V/s\n', ...
    verification.fb_capacitor_slope_V_per_s);
fprintf(fid,'i_cap=s*i_arm sign agreement: %.6f\n', ...
    verification.capacitor_current_sign_agreement);
fprintf(fid,'HB limited peak/fundamental: %.6f / %.6f kV\n', ...
    verification.hb_limited_phase_peak_kV,verification.hb_fundamental_peak_kV);
fprintf(fid,'Charge/discharge selection indices: %s / %s\n', ...
    mat2str(verification.charge_selected),mat2str(verification.discharge_selected));
fclose(fid);
disp(verification);

function peaks = fundamentalPeaks(t,v,f1)
peaks = zeros(1,size(v,2));
for phase = 1:size(v,2)
    basis = [sin(2*pi*f1*t),cos(2*pi*f1*t)];
    coefficient = basis\(v(:,phase)-mean(v(:,phase)));
    peaks(phase) = hypot(coefficient(1),coefficient(2));
end
end
