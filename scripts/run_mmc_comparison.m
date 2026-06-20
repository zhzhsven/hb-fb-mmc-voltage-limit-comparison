% RUN_MMC_COMPARISON Execute all HB/FB switching-level comparison cases.
run(fullfile(fileparts(mfilename('fullpath')),'init_mmc_comparison.m'));
if exist('Tstop_override','var')
    Tstop = Tstop_override;
end

signalNames = {'v_phase_command','v_phase_limited','v_phase_actual', ...
    'v_terminal_midpoint','i_load','arm_voltage_reference', ...
    'arm_voltage_quantized','v_arm_actual','inserted_count', ...
    'positive_count','negative_count','sm_switching_states', ...
    'v_capacitors','i_arm','i_dc'};
topologyNames = {'HB','FB'};
modelNames = {'mmc_hb_switching','mmc_fb_switching'};
if ~exist('force_cases','var')
    force_cases = {};
end
if ~exist('only_cases','var')
    only_cases = {};
end

fprintf('MMC comparison: Ts_elec = %.1f us, Ts_mod = %.1f us, Tstop = %.3f s\n', ...
    1e6*Ts_elec,1e6*Ts_mod,Tstop);
fprintf('HB: Vc = %.1f kV, installed arm = %.1f kV.\n', ...
    Vc_ref_HB/1e3,Varm_rated_HB/1e3);
fprintf('FB: Vc = %.1f kV, installed arm = +/-%.1f kV.\n', ...
    Vc_ref_FB/1e3,Varm_rated_FB/1e3);
fprintf('Required FB 7 kV arm range: %.1f kV to %.1f kV.\n', ...
    (Vdc/2-case_peaks(3))/1e3,(Vdc/2+case_peaks(3))/1e3);

for topologyIndex = 1:2
    topology_id = topologyIndex;
    if topology_id == 1
        Vc_ref = Vc_ref_HB;
        Varm_rated = Varm_rated_HB;
        Csm = Csm_HB;
        Larm = Larm_HB;
        Rarm = Rarm_HB;
        Kp_energy = Kp_energy_HB;
        Ki_energy = Ki_energy_HB;
        energy_current_limit = energy_current_limit_HB;
        common_voltage_limit = common_voltage_limit_HB;
        voltage_correction_limit = voltage_correction_limit_HB;
    else
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
    end
    for caseIndex = 1:numel(case_peaks)
        Vphase_cmd = case_peaks(caseIndex);
        caseName = sprintf('%s_%s',topologyNames{topologyIndex},case_labels{caseIndex});
        if ~isempty(only_cases) && ~ismember(caseName,only_cases)
            continue
        end
        resultFile = fullfile(project_root,'results',[caseName '.mat']);
        if isfile(resultFile) && ~ismember(caseName,force_cases)
            checkpoint = load(resultFile,'caseData');
            if isfield(checkpoint.caseData.meta,'model_revision') && ...
                    strcmp(checkpoint.caseData.meta.model_revision,model_revision) && ...
                    checkpoint.caseData.meta.Tstop == Tstop && ...
                    checkpoint.caseData.meta.Vc_ref == Vc_ref
                if ~isfield(checkpoint.caseData,'absolute_inserted_count')
                    caseData = checkpoint.caseData;
                    caseData.absolute_inserted_count = caseData.inserted_count;
                    caseData.absolute_inserted_count.data = abs( ...
                        caseData.absolute_inserted_count.data);
                    save(resultFile,'caseData','-v7.3');
                end
                fprintf('\nSkipping completed case %s.\n',caseName);
                continue
            end
        end
        fprintf('\nRunning %s ...\n',caseName);
        caseTimer = tic;

        in = Simulink.SimulationInput(modelNames{topologyIndex});
        in = setCaseVariables(in);
        in = in.setModelParameter('StopTime','Tstop', ...
            'ReturnWorkspaceOutputs','on');
        out = sim(in);

        caseData = struct;
        caseData.meta.case_name = caseName;
        caseData.meta.model_revision = model_revision;
        caseData.meta.topology = topologyNames{topologyIndex};
        caseData.meta.command_peak = Vphase_cmd;
        caseData.meta.Vdc = Vdc;
        caseData.meta.N = N;
        caseData.meta.Vc_ref = Vc_ref;
        caseData.meta.Varm_rated = Varm_rated;
        caseData.meta.Ts_elec = Ts_elec;
        caseData.meta.Ts_mod = Ts_mod;
        caseData.meta.Tstop = Tstop;
        caseData.meta.analysis_window = analysis_window;
        caseData.meta.Csm = Csm;
        caseData.meta.Larm = Larm;
        caseData.meta.Rarm = Rarm;
        caseData.meta.Rload = Rload;
        caseData.meta.Lload = Lload;
        caseData.meta.elapsed_seconds = toc(caseTimer);
        for signalIndex = 1:numel(signalNames)
            signal = out.get(signalNames{signalIndex});
            caseData.(signalNames{signalIndex}).time = signal.Time;
            caseData.(signalNames{signalIndex}).data = signal.Data;
        end
        caseData.absolute_inserted_count = caseData.inserted_count;
        caseData.absolute_inserted_count.data = abs( ...
            caseData.absolute_inserted_count.data);
        save(resultFile,'caseData','-v7.3');
        fprintf('Completed %s in %.1f s.\n',caseName,caseData.meta.elapsed_seconds);
        clear out in caseData signal
    end
end

fprintf('\nAll six switching cases completed. Run analyze_mmc_comparison.m next.\n');

function in = setCaseVariables(in)
names = {'Vdc','f1','N','Vc_ref','Varm_rated','Csm','Larm','Rarm', ...
    'Rload','Lload','Ts_mod','Ts_elec','dead_time','Tstop', ...
    'ramp_start','ramp_time','Vphase_cmd','topology_id', ...
    'Kp_energy','Ki_energy','energy_current_limit','circ_current_min', ...
    'circ_current_max','Kp_circ','Ki_circ','common_voltage_limit', ...
    'arm_balance_gain','arm_balance_limit_pu','sort_hysteresis_pu'};
names = [names,{'voltage_amp_tau','Kp_voltage','Ki_voltage', ...
    'voltage_control_delay','voltage_correction_limit'}];
for idx = 1:numel(names)
    in = in.setVariable(names{idx},evalin('caller',names{idx}));
end
end
