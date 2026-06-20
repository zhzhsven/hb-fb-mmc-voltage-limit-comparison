% PLOT_INSERTED_COUNT_ANALYSIS Phase-leg count interpretation for all cases.
run(fullfile(fileparts(mfilename('fullpath')),'init_mmc_comparison.m'));

caseLabels = {'4kV','5kV','7kV'};
phaseNames = {'A','B','C'};
for caseIndex = 1:numel(caseLabels)
    label = caseLabels{caseIndex};
    hbLoaded = load(fullfile(project_root,'results',['HB_' label '.mat']),'caseData');
    fbLoaded = load(fullfile(project_root,'results',['FB_' label '.mat']),'caseData');
    hb = hbLoaded.caseData;
    fb = fbLoaded.caseData;

    hbWindow = hb.inserted_count.time >= hb.meta.Tstop-0.04;
    fbWindow = fb.inserted_count.time >= fb.meta.Tstop-0.04;
    hbTime = hb.inserted_count.time(hbWindow);
    fbTime = fb.inserted_count.time(fbWindow);
    hbCount = hb.inserted_count.data(hbWindow,:);
    fbCount = fb.inserted_count.data(fbWindow,:);

    figure('Color','w','Position',[100 100 1200 850]);
    tiledlayout(3,1,'TileSpacing','compact');
    for phase = 1:3
        upper = 2*phase-1;
        lower = upper+1;
        nexttile; hold on; grid on;
        plot(hbTime,hbCount(:,upper),'b','LineWidth',0.9);
        plot(hbTime,hbCount(:,lower),'r','LineWidth',0.9);
        plot(hbTime,hbCount(:,upper)+hbCount(:,lower),'k','LineWidth',1.1);
        yline(N,'k--','N = 10');
        ylabel('count'); title(sprintf('HB %s, phase %s',label,phaseNames{phase}));
        if phase == 1
            legend('k_u','k_l','k_u+k_l','Location','bestoutside');
        end
    end
    xlabel('Time (s)');
    exportgraphics(gcf,fullfile(project_root,'figures', ...
        ['hb_leg_inserted_count_sums_' label '.png']),'Resolution',180);
    close(gcf);

    figure('Color','w','Position',[100 100 1200 850]);
    tiledlayout(3,1,'TileSpacing','compact');
    signedReference = Vdc/Vc_ref_FB;
    for phase = 1:3
        upper = 2*phase-1;
        lower = upper+1;
        nexttile; hold on; grid on;
        plot(fbTime,fbCount(:,upper),'b','LineWidth',0.9);
        plot(fbTime,fbCount(:,lower),'r','LineWidth',0.9);
        plot(fbTime,fbCount(:,upper)+fbCount(:,lower),'k','LineWidth',1.1);
        yline(signedReference,'k--',sprintf('Vdc/Vc = %.2f',signedReference));
        ylabel('signed count'); title(sprintf('FB %s, phase %s',label,phaseNames{phase}));
        if phase == 1
            legend('k_u','k_l','k_u+k_l','Location','bestoutside');
        end
    end
    xlabel('Time (s)');
    exportgraphics(gcf,fullfile(project_root,'figures', ...
        ['fb_leg_signed_count_sums_' label '.png']),'Resolution',180);
    close(gcf);

    positive = fb.positive_count.data(fbWindow,:);
    negative = fb.negative_count.data(fbWindow,:);
    figure('Color','w','Position',[100 100 1200 900]);
    tiledlayout(3,1,'TileSpacing','compact');
    for phase = 1:3
        upper = 2*phase-1;
        lower = upper+1;
        nexttile; hold on; grid on;
        plot(fbTime,positive(:,upper),'b','LineWidth',0.9);
        plot(fbTime,negative(:,upper),'b--','LineWidth',0.9);
        plot(fbTime,abs(fbCount(:,upper)),'c','LineWidth',1.0);
        plot(fbTime,positive(:,lower),'r','LineWidth',0.9);
        plot(fbTime,negative(:,lower),'r--','LineWidth',0.9);
        plot(fbTime,abs(fbCount(:,lower)),'m','LineWidth',1.0);
        ylabel('count'); title(sprintf('FB %s, phase %s',label,phaseNames{phase}));
        if phase == 1
            legend('upper +','upper -','abs(k_u)','lower +','lower -', ...
                'abs(k_l)','Location','bestoutside');
        end
    end
    xlabel('Time (s)');
    exportgraphics(gcf,fullfile(project_root,'figures', ...
        ['fb_leg_positive_negative_absolute_counts_' label '.png']), ...
        'Resolution',180);
    close(gcf);
end
