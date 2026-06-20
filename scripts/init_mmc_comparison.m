% INIT_MMC_COMPARISON Scaled 10 kV HB/FB MMC comparison parameters.
project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(project_root,'scripts'));
addpath(fullfile(project_root,'models'));

model_revision = '10kV_separate_capacitor_refs_v2';
Vdc = 10e3;                       % V, common DC-link voltage
f1 = 50;                          % Hz
N = 10;                           % submodules per arm
case_peaks = [4e3 5e3 7e3];       % V peak, phase to floating load neutral
case_labels = {'4kV','5kV','7kV'};

% Topology-specific capacitor and installed-arm designs.
Vc_ref_HB = Vdc/N;                % 1.0 kV, conventional HB design
Vc_ref_FB = 1.5e3;                % 1.5 kV, increased FB stored voltage
Varm_rated_HB = N*Vc_ref_HB;      % 10 kV, range 0...+10 kV
Varm_rated_FB = N*Vc_ref_FB;      % 15 kV, range -15...+15 kV

% C*Vc is matched between topologies to obtain comparable per-unit ripple.
Csm_HB = 15e-3;                   % F, 75 kJ nominal energy per HB arm
Csm_FB = 10e-3;                   % F, 112.5 kJ nominal energy per FB arm
Larm_HB = 10e-3;                  % H, medium-voltage arm reactor
Larm_FB = 10e-3;                  % H
Rarm_HB = 0.2;                    % ohm, arm damping/loss model
Rarm_FB = 0.2;                    % ohm
Rload = 10;                       % ohm per phase
Lload = 20e-3;                    % H per phase

Ts_mod = 50e-6;                   % s, NLM/sorting update
Ts_elec = 5e-6;                   % s, switching-network/local-solver step
dead_time = 5e-6;                 % s, one electrical step commutation dead time
Tstop = 0.22;                     % s, 8.5 cycles after the soft ramp
analysis_window = 0.08;           % s, final four complete cycles
ramp_start = 0.01;                % s
ramp_time = 0.04;                 % s

% Controller values. Voltage/current limits scale with the 10 kV system;
% gains retain the validated per-unit dynamics and account for the
% five-times-larger arm reactor.
Kp_energy_HB = 0.42;              % A/V
Ki_energy_HB = 18;                % A/(V*s)
Kp_energy_FB = 0.28;              % A/V
Ki_energy_FB = 12;                % A/(V*s)
energy_current_limit_HB = 300;    % A
energy_current_limit_FB = 300;    % A
circ_current_min = -100;          % A
circ_current_max = 600;           % A
Kp_circ = 11;                     % V/A
Ki_circ = 2100;                   % V/(A*s)
common_voltage_limit_HB = 2.0e3;  % V
common_voltage_limit_FB = 2.5e3;  % V
arm_balance_gain = 0.8;           % V/V
arm_balance_limit_pu = 0.25;      % fraction of one cell voltage
sort_hysteresis_pu = 0.005;       % 0.5% within-arm spread before reselection
voltage_amp_tau = 5e-3;           % s, three-phase synchronous amplitude filter
Kp_voltage = 0.30;                % V/V, FB fundamental-voltage regulator
Ki_voltage = 8;                   % 1/s
voltage_control_delay = 0.01;      % s after the soft ramp
voltage_correction_limit_HB = 0;  % V, HB retains the explicit clipped command
voltage_correction_limit_FB = 2e3;% V, below the FB physical arm margin

% Defaults let either model open interactively. The batch runner replaces
% these aliases with the topology-specific values before every simulation.
topology_id = 1;                   % 1 = HB, 2 = FB
Vphase_cmd = case_peaks(1);        % V peak
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

assert(Vc_ref_HB == 1e3 && Varm_rated_HB == 10e3, ...
    'HB capacitor/arm-voltage design is inconsistent.');
assert(Vc_ref_FB == 1.5e3 && Varm_rated_FB == 15e3, ...
    'FB capacitor/arm-voltage design is inconsistent.');
assert(Vdc/2-case_peaks(3) == -2e3, ...
    'The 7 kV FB upper-arm requirement must be -2 kV.');
assert(Vdc/2+case_peaks(3) == 12e3 && Varm_rated_FB >= 12e3, ...
    'The 7 kV FB lower-arm requirement exceeds installed arm voltage.');
assert(N*1e3 < Vdc/2+case_peaks(3), ...
    'The optional 1 kV/cell FB diagnostic must remain insufficient.');
