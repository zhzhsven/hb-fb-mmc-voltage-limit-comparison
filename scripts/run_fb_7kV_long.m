% RUN_FB_7KV_LONG Run only the 1.5 s FB-MMC 7 kV stability case.
run(fullfile(fileparts(mfilename('fullpath')),'init_mmc_comparison.m'));

resultFile = fullfile(project_root,'results','FB_7kV_long_1p5s.mat');
longRevision = [model_revision '_long_1p5s'];
if ~exist('force_long_run','var')
    force_long_run = false;
end
runNeeded = true;
if isfile(resultFile) && ~force_long_run
    checkpoint = load(resultFile,'caseData');
    runNeeded = ~strcmp(checkpoint.caseData.meta.model_revision,longRevision) || ...
        checkpoint.caseData.meta.Tstop ~= 1.5;
end

if runNeeded
    topology_id = 2;
    Vphase_cmd = 7e3;
    Vc_ref = Vc_ref_FB;
    Varm_rated = Varm_rated_FB;
    Csm = Csm_FB;
    Larm = Larm_FB;
    Rarm = Rarm_FB;
    Kp_energy = Kp_energy_FB;
    Ki_energy = Ki_energy_FB;
    energy_current_limit = energy_current_limit_FB;
    common_voltage_limit = common_voltage_limit_FB;
    voltage_correction_limit = voltage_correction_limit_FB;
    Tstop = 1.5;
    analysis_window = 0.3;

    fprintf('Running FB_7kV_long_1p5s (switching level, %.1f s) ...\n',Tstop);
    caseTimer = tic;
    in = Simulink.SimulationInput('mmc_fb_switching');
    in = setLongCaseVariables(in);
    in = in.setModelParameter('StopTime','Tstop','ReturnWorkspaceOutputs','on');
    out = sim(in);

    signalNames = {'v_phase_command','v_phase_limited','v_phase_actual', ...
        'v_terminal_midpoint','i_load','arm_voltage_reference', ...
        'arm_voltage_quantized','v_arm_actual','inserted_count', ...
        'positive_count','negative_count','sm_switching_states', ...
        'v_capacitors','i_arm','i_dc'};
    caseData = struct;
    caseData.meta.case_name = 'FB_7kV_long_1p5s';
    caseData.meta.model_revision = longRevision;
    caseData.meta.topology = 'FB';
    caseData.meta.command_peak = Vphase_cmd;
    caseData.meta.Vdc = Vdc;
    caseData.meta.N = N;
    caseData.meta.Vc_ref = Vc_ref;
    caseData.meta.Varm_rated = Varm_rated;
    caseData.meta.Csm = Csm;
    caseData.meta.Larm = Larm;
    caseData.meta.Rarm = Rarm;
    caseData.meta.Rload = Rload;
    caseData.meta.Lload = Lload;
    caseData.meta.Ts_elec = Ts_elec;
    caseData.meta.Ts_mod = Ts_mod;
    caseData.meta.Tstop = Tstop;
    caseData.meta.analysis_window = analysis_window;
    caseData.meta.elapsed_seconds = toc(caseTimer);
    for signalIndex = 1:numel(signalNames)
        signal = out.get(signalNames{signalIndex});
        caseData.(signalNames{signalIndex}).time = signal.Time;
        caseData.(signalNames{signalIndex}).data = signal.Data;
    end
    caseData.absolute_inserted_count = caseData.inserted_count;
    caseData.absolute_inserted_count.data = abs(caseData.inserted_count.data);
    save(resultFile,'caseData','-v7.3');
    fprintf('Completed FB_7kV_long_1p5s in %.1f s.\n',caseData.meta.elapsed_seconds);
else
    fprintf('Using completed checkpoint: %s\n',resultFile);
end

function in = setLongCaseVariables(in)
names = {'Vdc','f1','N','Vc_ref','Varm_rated','Csm','Larm','Rarm', ...
    'Rload','Lload','Ts_mod','Ts_elec','dead_time','Tstop', ...
    'ramp_start','ramp_time','Vphase_cmd','topology_id', ...
    'Kp_energy','Ki_energy','energy_current_limit','circ_current_min', ...
    'circ_current_max','Kp_circ','Ki_circ','common_voltage_limit', ...
    'arm_balance_gain','arm_balance_limit_pu','sort_hysteresis_pu', ...
    'voltage_amp_tau','Kp_voltage','Ki_voltage','voltage_control_delay', ...
    'voltage_correction_limit'};
for idx = 1:numel(names)
    in = in.setVariable(names{idx},evalin('caller',names{idx}));
end
end
