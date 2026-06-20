% ANALYZE_FB_7KV_LONG Long-duration FB 7 kV plots and quantitative checks.
run(fullfile(fileparts(mfilename('fullpath')),'init_mmc_comparison.m'));
resultFile = fullfile(project_root,'results','FB_7kV_long_1p5s.mat');
assert(isfile(resultFile),'Run scripts/run_fb_7kV_long.m first.');
loaded = load(resultFile,'caseData');
data = loaded.caseData;
assert(data.meta.Tstop == 1.5,'The long-run result is not 1.5 s.');

finalWindow = data.v_phase_actual.time >= data.meta.Tstop-0.3;
t = data.v_phase_actual.time(finalWindow);
v = data.v_phase_actual.data(finalWindow,:);
i = data.i_load.data(finalWindow,:);
vc = data.v_capacitors.data(finalWindow,:);
iarm = data.i_arm.data(finalWindow,:);
idc = data.i_dc.data(finalWindow,:);
states = data.sm_switching_states.data(finalWindow,:);

fundamental = zeros(1,3);
thd = zeros(1,3);
for phase = 1:3
    [fundamental(phase),thd(phase)] = harmonicMetrics(t,v(:,phase),f1,40);
end
icirc = 0.5*[iarm(:,1)+iarm(:,2),iarm(:,3)+iarm(:,4),iarm(:,5)+iarm(:,6)];
pdc = data.meta.Vdc*idc;
pac = sum(v.*i,2);
stateArmVoltage = squeeze(sum(reshape(states,[],N,6).*reshape(vc,[],N,6),2));

capacitorEnergy = 0.5*data.meta.Csm*sum(vc.^2,2);
armInductorEnergy = 0.5*data.meta.Larm*sum(iarm.^2,2);
loadInductorEnergy = 0.5*data.meta.Lload*sum(i.^2,2);
storedEnergy = capacitorEnergy+armInductorEnergy+loadInductorEnergy;
storedEnergyDrift = (storedEnergy(end)-storedEnergy(1))/(t(end)-t(1));
armResistorLoss = data.meta.Rarm*mean(sum(iarm.^2,2));
powerResidual = mean(pdc)-mean(pac)-storedEnergyDrift-armResistorLoss;

metrics = struct;
metrics.case_name = data.meta.case_name;
metrics.final_window_s = 0.3;
metrics.fundamental_peak_kV = mean(fundamental)/1e3;
metrics.thd_percent = mean(thd);
metrics.cap_start_min_kV = min(vc(1,:))/1e3;
metrics.cap_start_mean_kV = mean(vc(1,:))/1e3;
metrics.cap_start_max_kV = max(vc(1,:))/1e3;
metrics.cap_end_min_kV = min(vc(end,:))/1e3;
metrics.cap_end_mean_kV = mean(vc(end,:))/1e3;
metrics.cap_end_max_kV = max(vc(end,:))/1e3;
metrics.cap_window_min_kV = min(vc,[],'all')/1e3;
metrics.cap_window_mean_kV = mean(vc,'all')/1e3;
metrics.cap_window_max_kV = max(vc,[],'all')/1e3;
metrics.cap_ripple_pp_max_V = max(max(vc,[],1)-min(vc,[],1));
metrics.arm_current_peak_A = max(abs(iarm),[],'all');
metrics.circulating_current_peak_A = max(abs(icirc),[],'all');
metrics.cap_total_min_kV = min(data.v_capacitors.data,[],'all')/1e3;
metrics.cap_total_max_kV = max(data.v_capacitors.data,[],'all')/1e3;
metrics.arm_current_peak_total_A = max(abs(data.i_arm.data),[],'all');
allArmCurrent = data.i_arm.data;
allCirc = 0.5*[allArmCurrent(:,1)+allArmCurrent(:,2), ...
    allArmCurrent(:,3)+allArmCurrent(:,4), ...
    allArmCurrent(:,5)+allArmCurrent(:,6)];
metrics.circulating_current_peak_total_A = max(abs(allCirc),[],'all');
capTrend = polyfit(t,mean(vc,2),1);
metrics.cap_mean_slope_final_V_per_s = capTrend(1);
metrics.dc_power_mean_MW = mean(pdc)/1e6;
metrics.ac_power_mean_MW = mean(pac)/1e6;
metrics.stored_energy_drift_MW = storedEnergyDrift/1e6;
metrics.arm_resistor_loss_MW = armResistorLoss/1e6;
metrics.power_balance_raw_error_percent = 100*abs(mean(pdc)-mean(pac))/abs(mean(pdc));
metrics.power_balance_residual_percent = 100*abs(powerResidual)/abs(mean(pdc));
metrics.negative_state_samples_final = nnz(states < 0);
metrics.negative_state_samples_total = nnz(data.sm_switching_states.data < 0);
metrics.negative_count_max = max(data.negative_count.data,[],'all');
metrics.state_arm_voltage_min_kV = min(stateArmVoltage,[],'all')/1e3;
metrics.has_nan = any(~isfinite([v(:);i(:);vc(:);iarm(:);idc(:)]));

summary = struct2table(metrics);
writetable(summary,fullfile(project_root,'results','FB_7kV_long_1p5s_metrics.csv'));
save(fullfile(project_root,'results','FB_7kV_long_1p5s_metrics.mat'), ...
    'summary','metrics');
writeLongReport(metrics,fullfile(project_root,'results', ...
    'FB_7kV_long_1p5s_report.txt'));

fullTime = data.v_phase_actual.time;
plotIndex = unique(round(linspace(1,numel(fullTime),min(20000,numel(fullTime)))));
tp = fullTime(plotIndex);

figure('Color','w','Position',[100 100 1300 800]);
tiledlayout(2,1,'TileSpacing','compact');
nexttile; plot(t,v/1e3,'LineWidth',0.8); grid on; xlim([1.2 1.5]);
ylabel('kV'); title('FB 7 kV: load phase voltages (final 0.3 s)');
legend('v_{aN}','v_{bN}','v_{cN}','Location','bestoutside');
nexttile; plot(t,i/1e3,'LineWidth',0.8); grid on; xlim([1.2 1.5]);
xlabel('Time (s)'); ylabel('kA'); title('Load currents (final 0.3 s)');
legend('i_a','i_b','i_c','Location','bestoutside');
exportgraphics(gcf,fullfile(project_root,'figures', ...
    'fb_7kV_long_output_voltage_current.png'),'Resolution',180); close(gcf);

figure('Color','w','Position',[100 100 1300 800]);
tiledlayout(2,1,'TileSpacing','compact');
nexttile; plot(tp,data.v_arm_actual.data(plotIndex,5:6)/1e3); grid on;
ylabel('kV'); title('Phase C upper/lower arm voltages');
legend('C upper','C lower','Location','bestoutside');
nexttile; plot(tp,data.i_arm.data(plotIndex,5:6)/1e3); grid on;
xlabel('Time (s)'); ylabel('kA'); title('Phase C upper/lower arm currents');
legend('C upper','C lower','Location','bestoutside');
exportgraphics(gcf,fullfile(project_root,'figures', ...
    'fb_7kV_long_phaseC_arm_voltage_current.png'),'Resolution',180); close(gcf);

signed = data.inserted_count.data(plotIndex,5:6);
positive = data.positive_count.data(plotIndex,5:6);
negative = data.negative_count.data(plotIndex,5:6);
figure('Color','w','Position',[100 100 1300 900]);
tiledlayout(3,1,'TileSpacing','compact');
nexttile; plot(tp,signed); hold on; plot(tp,sum(signed,2),'k','LineWidth',1.1);
yline(Vdc/Vc_ref_FB,'k--',sprintf('Vdc/Vc = %.2f',Vdc/Vc_ref_FB)); grid on;
ylabel('signed count'); title('Phase C signed inserted counts');
legend('upper','lower','sum','Location','bestoutside');
nexttile; plot(tp,[positive,negative]); grid on; ylabel('count');
title('Phase C positive and negative insertion counts');
legend('upper +','lower +','upper -','lower -','Location','bestoutside');
nexttile; plot(tp,abs(signed)); grid on; xlabel('Time (s)'); ylabel('count');
title('Phase C absolute inserted counts');
legend('abs(k_u)','abs(k_l)','Location','bestoutside');
exportgraphics(gcf,fullfile(project_root,'figures', ...
    'fb_7kV_long_phaseC_insertion_counts.png'),'Resolution',180); close(gcf);

vcFull = data.v_capacitors.data(plotIndex,:);
iarmFull = data.i_arm.data(plotIndex,:);
icircFull = 0.5*[iarmFull(:,1)+iarmFull(:,2), ...
    iarmFull(:,3)+iarmFull(:,4),iarmFull(:,5)+iarmFull(:,6)];
pdcFull = data.meta.Vdc*data.i_dc.data(plotIndex,:);
pacFull = sum(data.v_phase_actual.data(plotIndex,:).* ...
    data.i_load.data(plotIndex,:),2);
figure('Color','w','Position',[100 100 1300 950]);
tiledlayout(3,1,'TileSpacing','compact');
nexttile; plot(tp,[min(vcFull,[],2),mean(vcFull,2),max(vcFull,[],2)]/1e3);
grid on; ylabel('kV'); title('All-cell capacitor-voltage envelope');
legend('minimum','mean','maximum','Location','bestoutside');
nexttile; plot(tp,icircFull/1e3); grid on; ylabel('kA');
title('Circulating currents'); legend('phase A','phase B','phase C','Location','bestoutside');
nexttile; plot(tp,[pdcFull,pacFull]/1e6); grid on; xlabel('Time (s)'); ylabel('MW');
title('DC and AC active power'); legend('P_{dc}','P_{ac}','Location','bestoutside');
exportgraphics(gcf,fullfile(project_root,'figures', ...
    'fb_7kV_long_stability_summary.png'),'Resolution',180); close(gcf);

disp(summary);

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

function writeLongReport(metrics,fileName)
fid = fopen(fileName,'w');
fprintf(fid,'FB 7 kV long-duration switching result (1.5 s)\n\n');
fprintf(fid,'Final-window fundamental: %.6f kVpk\n',metrics.fundamental_peak_kV);
fprintf(fid,'Final-window THD: %.6f %%\n',metrics.thd_percent);
fprintf(fid,'Capacitors at window start min/mean/max: %.6f / %.6f / %.6f kV\n', ...
    metrics.cap_start_min_kV,metrics.cap_start_mean_kV,metrics.cap_start_max_kV);
fprintf(fid,'Capacitors at window end min/mean/max: %.6f / %.6f / %.6f kV\n', ...
    metrics.cap_end_min_kV,metrics.cap_end_mean_kV,metrics.cap_end_max_kV);
fprintf(fid,'Final-window capacitor range: %.6f to %.6f kV\n', ...
    metrics.cap_window_min_kV,metrics.cap_window_max_kV);
fprintf(fid,'Worst individual capacitor ripple: %.6f Vpp\n',metrics.cap_ripple_pp_max_V);
fprintf(fid,'Peak arm/circulating current: %.6f / %.6f A\n', ...
    metrics.arm_current_peak_A,metrics.circulating_current_peak_A);
fprintf(fid,'Full-run capacitor range: %.6f to %.6f kV\n', ...
    metrics.cap_total_min_kV,metrics.cap_total_max_kV);
fprintf(fid,'Full-run peak arm/circulating current: %.6f / %.6f A\n', ...
    metrics.arm_current_peak_total_A,metrics.circulating_current_peak_total_A);
fprintf(fid,'Final-window capacitor mean slope: %+.6f V/s\n', ...
    metrics.cap_mean_slope_final_V_per_s);
fprintf(fid,'Mean DC/AC power: %.6f / %.6f MW\n', ...
    metrics.dc_power_mean_MW,metrics.ac_power_mean_MW);
fprintf(fid,'Raw/corrected power residual: %.6f / %.6f %%\n', ...
    metrics.power_balance_raw_error_percent,metrics.power_balance_residual_percent);
fprintf(fid,'Negative state samples final/total: %d / %d\n', ...
    metrics.negative_state_samples_final,metrics.negative_state_samples_total);
fprintf(fid,'Maximum negative count: %.0f\n',metrics.negative_count_max);
fprintf(fid,'Minimum state-derived arm voltage: %.6f kV\n', ...
    metrics.state_arm_voltage_min_kV);
fprintf(fid,'NaN or Inf present: %d\n',metrics.has_nan);
fclose(fid);
end
