% ANALYZE_MMC_SCALED Analyze the six scaled 10 kV switching cases.
run(fullfile(fileparts(mfilename('fullpath')),'init_mmc_comparison.m'));

caseNames = {'HB_4kV','HB_5kV','HB_7kV','FB_4kV','FB_5kV','FB_7kV'};
metricCells = cell(1,numel(caseNames));
cases = struct;
for caseIndex = 1:numel(caseNames)
    resultFile = fullfile(project_root,'results',[caseNames{caseIndex} '.mat']);
    assert(isfile(resultFile),'Missing result file: %s',resultFile);
    loaded = load(resultFile,'caseData');
    assert(strcmp(loaded.caseData.meta.model_revision,model_revision), ...
        'Result %s belongs to a different model revision.',caseNames{caseIndex});
    cases.(caseNames{caseIndex}) = loaded.caseData;
    metricCells{caseIndex} = calculateMetrics(loaded.caseData,f1);
end
metrics = [metricCells{:}];

summary = struct2table(metrics);
writetable(summary,fullfile(project_root,'results','mmc_comparison_metrics.csv'));
save(fullfile(project_root,'results','mmc_comparison_metrics.mat'),'summary','metrics');
writeTextReport(summary,fullfile(project_root,'results','mmc_comparison_report.txt'));

makeAllCasePhasePlots(cases,caseNames,project_root);
makePhaseComparison(cases,caseNames,project_root);
makeHBLimiterPlot(cases.HB_7kV,project_root);
makeSevenKilovoltPlots(cases,project_root);
makeCapabilityDiagnostic(project_root,Vdc,Varm_rated_HB,Varm_rated_FB);
makeMetricPlot(summary,project_root);

disp(summary(:,{'case_name','fundamental_peak_kV','tracking_error_percent', ...
    'thd_percent','cap_mean_kV','cap_ripple_pp_max_V', ...
    'cap_mean_slope_V_per_s','circulating_current_peak_A', ...
    'negative_count_max','state_arm_voltage_min_kV', ...
    'power_balance_residual_percent','has_nan'}));

function metric = calculateMetrics(caseData,f1)
t = caseData.v_phase_actual.time;
steady = t >= caseData.meta.Tstop-caseData.meta.analysis_window;
tt = t(steady);
v = caseData.v_phase_actual.data(steady,:);
i = caseData.i_load.data(steady,:);
vc = caseData.v_capacitors.data(steady,:);
iarm = caseData.i_arm.data(steady,:);
idc = caseData.i_dc.data(steady,:);
armActual = caseData.v_arm_actual.data(steady,:);
armRef = caseData.arm_voltage_reference.data(steady,:);
armQuant = caseData.arm_voltage_quantized.data(steady,:);
counts = caseData.inserted_count.data(steady,:);
neg = caseData.negative_count.data(steady,:);
states = caseData.sm_switching_states.data(steady,:);

fund = zeros(1,3);
thd = fund;
for phase = 1:3
    [fund(phase),thd(phase)] = harmonicMetrics(tt,v(:,phase),f1,40);
end

icirc = 0.5*[iarm(:,1)+iarm(:,2),iarm(:,3)+iarm(:,4), ...
    iarm(:,5)+iarm(:,6)];
pac = sum(v.*i,2);
pdc = caseData.meta.Vdc*idc;
stateArmVoltage = squeeze(sum(reshape(states,[],10,6).* ...
    reshape(vc,[],10,6),2));
vcByArm = reshape(vc,[],10,6);
withinArmSpread = squeeze(max(vcByArm,[],2)-min(vcByArm,[],2));

meanVcTrace = mean(vc,2);
vcTrend = polyfit(tt,meanVcTrace,1);
capacitorEnergy = 0.5*caseData.meta.Csm*sum(vc.^2,2);
armInductorEnergy = 0.5*caseData.meta.Larm*sum(iarm.^2,2);
loadInductorEnergy = 0.5*caseData.meta.Lload*sum(i.^2,2);
storedEnergy = capacitorEnergy+armInductorEnergy+loadInductorEnergy;
storedEnergyDrift = (storedEnergy(end)-storedEnergy(1))/(tt(end)-tt(1));
armResistorLoss = caseData.meta.Rarm*mean(sum(iarm.^2,2));
powerResidual = mean(pdc)-mean(pac)-storedEnergyDrift-armResistorLoss;

legCountSum = [counts(:,1)+counts(:,2),counts(:,3)+counts(:,4), ...
    counts(:,5)+counts(:,6)];
expectedCountSum = caseData.meta.Vdc/caseData.meta.Vc_ref;

metric.case_name = caseData.meta.case_name;
metric.topology = caseData.meta.topology;
metric.command_peak_V = caseData.meta.command_peak;
metric.command_peak_kV = caseData.meta.command_peak/1e3;
metric.limited_command_peak_kV = max(abs( ...
    caseData.v_phase_limited.data(steady,:)),[],'all')/1e3;
metric.raw_peak_kV = mean(max(abs(v),[],1))/1e3;
metric.fundamental_peak_V = mean(fund);
metric.fundamental_peak_kV = mean(fund)/1e3;
metric.tracking_error_percent = 100*(mean(fund)-caseData.meta.command_peak)/ ...
    caseData.meta.command_peak;
metric.rms_kV = mean(rms(v,1))/1e3;
metric.thd_percent = mean(thd);
metric.cap_reference_kV = caseData.meta.Vc_ref/1e3;
metric.cap_mean_kV = mean(vc,'all')/1e3;
metric.cap_mean_start_kV = meanVcTrace(1)/1e3;
metric.cap_mean_end_kV = meanVcTrace(end)/1e3;
metric.cap_endpoint_error_percent = 100*(meanVcTrace(end)- ...
    caseData.meta.Vc_ref)/caseData.meta.Vc_ref;
metric.cap_min_kV = min(vc,[],'all')/1e3;
metric.cap_max_kV = max(vc,[],'all')/1e3;
metric.cap_ripple_pp_max_V = max(max(vc,[],1)-min(vc,[],1));
metric.cap_max_deviation_V = max(abs(vc-caseData.meta.Vc_ref),[],'all');
metric.within_arm_spread_max_V = max(withinArmSpread,[],'all');
metric.cap_mean_slope_V_per_s = vcTrend(1);
metric.cap_mean_slope_percent_per_s = 100*vcTrend(1)/caseData.meta.Vc_ref;
metric.arm_current_peak_A = max(abs(iarm),[],'all');
metric.circulating_current_peak_A = max(abs(icirc),[],'all');
metric.circulating_current_mean_A = mean(icirc,'all');
metric.dc_current_mean_A = mean(idc);
metric.dc_power_mean_MW = mean(pdc)/1e6;
metric.ac_power_mean_MW = mean(pac)/1e6;
metric.stored_energy_drift_MW = storedEnergyDrift/1e6;
metric.arm_resistor_loss_MW = armResistorLoss/1e6;
metric.power_balance_raw_error_percent = 100*abs(mean(pdc)-mean(pac))/ ...
    max(abs(mean(pdc)),1);
metric.power_balance_residual_percent = 100*abs(powerResidual)/ ...
    max(abs(mean(pdc)),1);
metric.actual_arm_voltage_min_kV = min(armActual,[],'all')/1e3;
metric.actual_arm_voltage_max_kV = max(armActual,[],'all')/1e3;
metric.state_arm_voltage_min_kV = min(stateArmVoltage,[],'all')/1e3;
metric.state_arm_voltage_max_kV = max(stateArmVoltage,[],'all')/1e3;
metric.arm_reference_min_kV = min(armRef,[],'all')/1e3;
metric.arm_reference_max_kV = max(armRef,[],'all')/1e3;
metric.nlm_error_max_V = max(abs(armRef-armQuant),[],'all');
metric.count_sum_mean = mean(legCountSum,'all');
metric.count_sum_expected = expectedCountSum;
metric.count_sum_rms_error = rms(legCountSum-expectedCountSum,'all');
metric.negative_count_max = max(neg,[],'all');
metric.negative_state_samples = nnz(states < 0);
metric.has_nan = any(~isfinite([v(:);i(:);vc(:);iarm(:);idc(:);armActual(:)]));
end

function [fundamentalPeak,thdPercent] = harmonicMetrics(t,x,f1,maxHarmonic)
x = x-mean(x);
amplitudes = zeros(maxHarmonic,1);
for harmonic = 1:maxHarmonic
    basis = [sin(2*pi*harmonic*f1*t),cos(2*pi*harmonic*f1*t)];
    coefficient = basis\x;
    amplitudes(harmonic) = hypot(coefficient(1),coefficient(2));
end
fundamentalPeak = amplitudes(1);
thdPercent = 100*sqrt(sum(amplitudes(2:end).^2))/max(fundamentalPeak,eps);
end

function makeAllCasePhasePlots(cases,caseNames,projectRoot)
for caseIndex = 1:numel(caseNames)
    data = cases.(caseNames{caseIndex});
    window = data.v_phase_actual.time >= data.meta.Tstop-0.04;
    t = data.v_phase_actual.time(window);
    figure('Color','w','Position',[100 100 1200 650]);
    plot(t,data.v_phase_command.data(window,:)/1e3,'--','LineWidth',0.9);
    hold on; plot(t,data.v_phase_actual.data(window,:)/1e3,'LineWidth',0.9);
    grid on; xlabel('Time (s)'); ylabel('kV');
    title(sprintf('%s: commanded and actual load phase voltages',caseNames{caseIndex}));
    legend('cmd a','cmd b','cmd c','actual a','actual b','actual c', ...
        'Location','bestoutside');
    exportgraphics(gcf,fullfile(projectRoot,'figures', ...
        ['phase_voltages_' caseNames{caseIndex} '.png']),'Resolution',180);
    close(gcf);
end
end

function makePhaseComparison(cases,caseNames,projectRoot)
figure('Color','w','Position',[100 100 1200 850]);
tiledlayout(3,1,'TileSpacing','compact');
for row = 1:3
    hb = cases.(caseNames{row}); fb = cases.(caseNames{row+3});
    hbWindow = hb.v_phase_actual.time >= hb.meta.Tstop-0.04;
    fbWindow = fb.v_phase_actual.time >= fb.meta.Tstop-0.04;
    nexttile; hold on; grid on;
    plot(hb.v_phase_command.time(hbWindow), ...
        hb.v_phase_command.data(hbWindow,1)/1e3,'k--');
    plot(hb.v_phase_actual.time(hbWindow), ...
        hb.v_phase_actual.data(hbWindow,1)/1e3,'b');
    plot(fb.v_phase_actual.time(fbWindow), ...
        fb.v_phase_actual.data(fbWindow,1)/1e3,'r');
    ylabel('kV'); title(sprintf('%.0f kV phase command',hb.meta.command_peak/1e3));
    if row == 1
        legend('command','HB actual','FB actual','Location','bestoutside');
    end
end
xlabel('Time (s)');
exportgraphics(gcf,fullfile(projectRoot,'figures', ...
    'phase_voltage_comparison.png'),'Resolution',180); close(gcf);
end

function makeHBLimiterPlot(hb,projectRoot)
window = hb.v_phase_actual.time >= hb.meta.Tstop-0.04;
t = hb.v_phase_actual.time(window);
savePlot(t,[hb.v_phase_command.data(window,1), ...
    hb.v_phase_limited.data(window,1),hb.v_phase_actual.data(window,1)]/1e3, ...
    {'original 7 kV command','limited command','actual phase voltage'}, ...
    'HB 7 kV request: explicit +/-5 kV limiter','kV', ...
    fullfile(projectRoot,'figures','hb_command_limiter_7kV.png'));
end

function makeSevenKilovoltPlots(cases,projectRoot)
hb = cases.HB_7kV; fb = cases.FB_7kV;
window = fb.v_phase_actual.time >= fb.meta.Tstop-0.04;
t = fb.v_phase_actual.time(window);
stateArmVoltage = calculateStateArmVoltage(fb,window);
statePhaseVoltage = 0.5*[stateArmVoltage(:,2)-stateArmVoltage(:,1), ...
    stateArmVoltage(:,4)-stateArmVoltage(:,3), ...
    stateArmVoltage(:,6)-stateArmVoltage(:,5)];
statePhaseVoltage = statePhaseVoltage-mean(statePhaseVoltage,2);
savePlot(t,[fb.v_phase_command.data(window,1), ...
    fb.v_phase_actual.data(window,1),statePhaseVoltage(:,1)]/1e3, ...
    {'command','electrical output','state x measured Vc'}, ...
    'FB 7 kV NLM staircase and physical output','kV', ...
    fullfile(projectRoot,'figures','nlm_staircase_7kV.png'));

v = fb.v_phase_actual.data(window,:);
savePlot(t,[v(:,1)-v(:,2),v(:,2)-v(:,3),v(:,3)-v(:,1)]/1e3, ...
    {'v_{ab}','v_{bc}','v_{ca}'},'FB 7 kV line-to-line voltages','kV', ...
    fullfile(projectRoot,'figures','line_to_line_7kV.png'));
savePlot(t,fb.i_load.data(window,:)/1e3,{'i_a','i_b','i_c'}, ...
    'FB 7 kV load currents','kA', ...
    fullfile(projectRoot,'figures','load_currents_7kV.png'));

figure('Color','w','Position',[100 100 1200 850]); tiledlayout(3,2,'TileSpacing','compact');
for arm = 1:6
    nexttile; hold on; grid on;
    plot(t,fb.arm_voltage_reference.data(window,arm)/1e3,'k--');
    plot(t,fb.v_arm_actual.data(window,arm)/1e3,'b');
    title(sprintf('Arm %d',arm)); ylabel('kV');
end
legend('reference','electrical','Location','best');
exportgraphics(gcf,fullfile(projectRoot,'figures','arm_voltages_7kV.png'), ...
    'Resolution',180); close(gcf);

savePlot(t,fb.inserted_count.data(window,:),compose('arm %d',1:6), ...
    'FB signed inserted-submodule count','signed count', ...
    fullfile(projectRoot,'figures','inserted_counts_7kV.png'));
savePlot(t,abs(fb.inserted_count.data(window,:)),compose('arm %d',1:6), ...
    'FB absolute inserted-submodule count','count', ...
    fullfile(projectRoot,'figures','absolute_inserted_counts_7kV.png'));
savePlot(t,[fb.positive_count.data(window,:),fb.negative_count.data(window,:)], ...
    [compose('pos %d',1:6),compose('neg %d',1:6)], ...
    'FB positive and negative insertion counts','count', ...
    fullfile(projectRoot,'figures','fb_positive_negative_counts_7kV.png'));
savePlot(t,fb.v_capacitors.data(window,:)/1e3,compose('SM %d',1:60), ...
    'All FB submodule capacitor voltages','kV', ...
    fullfile(projectRoot,'figures','capacitor_voltages_7kV.png'),false);

vc = reshape(fb.v_capacitors.data(window,:),numel(t),10,6);
figure('Color','w','Position',[100 100 1200 850]); tiledlayout(3,2,'TileSpacing','compact');
for arm = 1:6
    nexttile; hold on; grid on; x = squeeze(vc(:,:,arm))/1e3;
    plot(t,min(x,[],2),'b'); plot(t,mean(x,2),'k'); plot(t,max(x,[],2),'r');
    title(sprintf('Arm %d',arm)); ylabel('kV');
end
legend('min','mean','max','Location','best');
exportgraphics(gcf,fullfile(projectRoot,'figures','capacitor_envelopes_7kV.png'), ...
    'Resolution',180); close(gcf);

savePlot(t,fb.i_arm.data(window,:)/1e3,compose('arm %d',1:6), ...
    'FB upper- and lower-arm currents','kA', ...
    fullfile(projectRoot,'figures','arm_currents_7kV.png'));
iarm = fb.i_arm.data(window,:);
icirc = 0.5*[iarm(:,1)+iarm(:,2),iarm(:,3)+iarm(:,4),iarm(:,5)+iarm(:,6)];
savePlot(t,icirc/1e3,{'phase A','phase B','phase C'}, ...
    'FB circulating currents','kA', ...
    fullfile(projectRoot,'figures','circulating_currents_7kV.png'));

pdc = fb.meta.Vdc*fb.i_dc.data(window,:);
pac = sum(fb.v_phase_actual.data(window,:).*fb.i_load.data(window,:),2);
savePlot(t,[fb.i_dc.data(window,:)/1e3,pdc/1e6], ...
    {'DC current (kA)','DC power (MW)'},'FB DC-side current and power','kA / MW', ...
    fullfile(projectRoot,'figures','dc_current_power_7kV.png'));
savePlot(t,pac/1e6,{'P_{ac}'},'FB AC active power','MW', ...
    fullfile(projectRoot,'figures','ac_power_7kV.png'));

savePlot(t,[fb.v_arm_actual.data(window,1),stateArmVoltage(:,1), ...
    fb.arm_voltage_reference.data(window,1)]/1e3, ...
    {'electrical arm V','state x measured Vc','arm reference'}, ...
    'FB 7 kV evidence of physical negative insertion','kV', ...
    fullfile(projectRoot,'figures','negative_insertion_evidence.png'));

vterm = fb.v_terminal_midpoint.data(window,:);
savePlot(t,[fb.v_phase_actual.data(window,:),vterm]/1e3, ...
    {'load a-N','load b-N','load c-N','terminal a-mid', ...
    'terminal b-mid','terminal c-mid'}, ...
    'Load phase voltage versus DC-midpoint terminal voltage','kV', ...
    fullfile(projectRoot,'figures','phase_vs_midpoint_voltage.png'));

hbWindow = hb.v_phase_actual.time >= hb.meta.Tstop-0.04;
savePlot(hb.v_phase_actual.time(hbWindow), ...
    [hb.v_phase_actual.data(hbWindow,1),fb.v_phase_actual.data(window,1)]/1e3, ...
    {'HB phase A','FB phase A'},'HB saturation versus FB 7 kV operation','kV', ...
    fullfile(projectRoot,'figures','hb_fb_7kV_output.png'));
end

function stateArmVoltage = calculateStateArmVoltage(data,window)
states = reshape(data.sm_switching_states.data(window,:),[],10,6);
vcaps = reshape(data.v_capacitors.data(window,:),[],10,6);
stateArmVoltage = squeeze(sum(states.*vcaps,2));
end

function makeCapabilityDiagnostic(projectRoot,Vdc,VarmHB,VarmFB)
requiredPositiveArm = Vdc/2+7e3;
figure('Color','w','Position',[100 100 1100 650]);
values = [VarmHB,VarmFB]/1e3;
bars = bar(1:2,values,0.62,'FaceColor','flat');
bars.CData = [0.85 0.33 0.10;0.47 0.67 0.19];
xticks(1:2); xticklabels({'10 cells at 1.0 kV/cell','10 cells at 1.5 kV/cell'});
ylabel('Available positive arm voltage (kV)'); grid on; ylim([0 17]);
yline(requiredPositiveArm/1e3,'--k','+12 kV required', ...
    'LineWidth',1.5,'LabelHorizontalAlignment','left');
title('Installed positive arm-voltage requirement for 7 kV phase-voltage operation');
subtitle('Vdc = 10 kV; required arm-reference range is -2 kV to +12 kV');
text(1:2,values+0.35,compose('%.1f kV',values), ...
    'HorizontalAlignment','center','FontWeight','bold');
exportgraphics(gcf,fullfile(projectRoot,'figures', ...
    'fb_installed_voltage_diagnostic.png'),'Resolution',180); close(gcf);
end

function makeMetricPlot(summary,projectRoot)
figure('Color','w','Position',[100 100 1150 520]); tiledlayout(1,2);
nexttile; bar(categorical(summary.case_name),summary.fundamental_peak_kV);
ylabel('kV peak'); title('Fundamental load phase voltage'); grid on;
nexttile; bar(categorical(summary.case_name),summary.cap_ripple_pp_max_V);
ylabel('V p-p'); title('Worst individual capacitor ripple'); grid on;
exportgraphics(gcf,fullfile(projectRoot,'figures','summary_metrics.png'), ...
    'Resolution',180); close(gcf);
end

function savePlot(t,y,labels,plotTitle,yLabel,fileName,showLegend)
if nargin < 7
    showLegend = true;
end
figure('Color','w','Position',[100 100 1200 600]);
plot(t,y,'LineWidth',0.9); grid on; xlabel('Time (s)'); ylabel(yLabel); title(plotTitle);
if showLegend
    legend(labels,'Location','bestoutside');
end
exportgraphics(gcf,fileName,'Resolution',180); close(gcf);
end

function writeTextReport(summary,fileName)
fid = fopen(fileName,'w');
fprintf(fid,'10 kV HB-MMC versus FB-MMC switching comparison\n\n');
for row = 1:height(summary)
    fprintf(fid,[ ...
        '%s: command %.1f kV, fundamental %.3f kVpk, tracking error %+.2f%%, ' ...
        'RMS %.3f kV, THD %.2f%%, Vc %.3f kV (%.3f..%.3f), ' ...
        'ripple %.2f Vpp, Vc slope %+.2f V/s, Icir peak %.2f A, ' ...
        'Pdc %.3f MW, Pac %.3f MW, corrected power residual %.2f%%, ' ...
        'negative count %.0f, state-arm minimum %.3f kV, NaN=%d\n'], ...
        summary.case_name{row},summary.command_peak_kV(row), ...
        summary.fundamental_peak_kV(row),summary.tracking_error_percent(row), ...
        summary.rms_kV(row),summary.thd_percent(row),summary.cap_mean_kV(row), ...
        summary.cap_min_kV(row),summary.cap_max_kV(row), ...
        summary.cap_ripple_pp_max_V(row),summary.cap_mean_slope_V_per_s(row), ...
        summary.circulating_current_peak_A(row),summary.dc_power_mean_MW(row), ...
        summary.ac_power_mean_MW(row),summary.power_balance_residual_percent(row), ...
        summary.negative_count_max(row),summary.state_arm_voltage_min_kV(row), ...
        summary.has_nan(row));
end
fclose(fid);
end
