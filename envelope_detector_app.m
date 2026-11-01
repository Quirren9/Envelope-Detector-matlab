function envelope_detector_app
% ENVELOPE_DETECTOR_APP  Live explorer for AM envelope detection with noise.
%   Run by typing envelope_detector_app in the Command Window.
%   Requires Signal Processing Toolbox (butter, filtfilt, sosfilt, hann, freqz).
%
%   Detector: rectifier + Butterworth low-pass (the digital version of a
%   diode + RC envelope detector).
%
%   Every parameter has a slider AND a number box:
%     - Type an exact value in the box and press Enter.
%     - Sliders snap to steps that scale with the value:
%         frequencies keep 2 significant digits
%         (10-99 -> steps of 1, 100-999 -> 10, 1000-9999 -> 100, 10000+ -> 1000)
%         m -> 0.01, SNR -> 0.5 dB, order -> 1
%     - Frequency sliders are logarithmic.
%
%   Spectrum plot: dB relative to the DC level of the rectified signal.
%   For a full-wave rectifier the f_m peak then sits at 20*log10(m) dB,
%   so you can read the modulation index straight off the plot.

fs = 200e3;                              % fixed sample rate (Hz)
rng(1);                                  % same noise pattern every update
noiseBase = randn(1, round(0.3*fs) + 1);

% ---------- default values ----------
p.fc        = 10e3;    % carrier frequency (Hz)
p.fm        = 200;     % message frequency (Hz)
p.m         = 0.5;     % modulation index
p.snr       = 15;      % signal-to-noise ratio (dB)
p.fcut      = 1000;    % low-pass cutoff (Hz)
p.order     = 4;       % Butterworth order
p.fullWave  = true;    % full-wave or half-wave rectifier
p.zeroPhase = true;    % filtfilt (no delay) or filter (realistic delay)
p0 = p;                % kept for the reset button
labelSize = 13;        % font size of the spectrum marker labels
ui = struct();         % handles to each slider + number box

% ---------- layout ----------
fig  = uifigure('Name','Envelope Detector Explorer','Position',[80 80 1250 760]);
main = uigridlayout(fig,[1 2]);
main.ColumnWidth = {330,'1x'};

ctrl = uigridlayout(main,[16 2]);
ctrl.ColumnWidth = {'1x',95};
ctrl.RowHeight   = [repmat({'fit'},1,15) {'1x'}];
ctrl.RowSpacing  = 6;

plots = uigridlayout(main,[2 1]);
plots.RowHeight = {'1x','1x'};
ax1 = uiaxes(plots);
ax2 = uiaxes(plots);

% ---------- controls ----------
%                 label                  key     limits       format  log?
row = 1;
row = addControl(row,'Carrier fc (Hz)',    'fc',   [2e3 40e3], '%.0f', true);
row = addControl(row,'Message fm (Hz)',    'fm',   [20 3000],  '%.0f', true);
row = addControl(row,'Modulation index m', 'm',    [0 1.5],    '%.2f', false);
row = addControl(row,'SNR (dB)',           'snr',  [-5 40],    '%.1f', false);
row = addControl(row,'LPF cutoff (Hz)',    'fcut', [20 20e3],  '%.0f', true);
row = addControl(row,'Filter order',       'order',[1 8],      '%d',   false);

dd = uidropdown(ctrl,'Items',{'Full-wave','Half-wave'},'Value','Full-wave', ...
    'ValueChangedFcn',@(s,~) setOpt('fullWave', strcmp(s.Value,'Full-wave')));
dd.Layout.Row = row; dd.Layout.Column = [1 2]; row = row + 1;

cb = uicheckbox(ctrl,'Text','Zero-phase filter (filtfilt)','Value',true, ...
    'ValueChangedFcn',@(s,~) setOpt('zeroPhase', s.Value));
cb.Layout.Row = row; cb.Layout.Column = [1 2]; row = row + 1;

btn = uibutton(ctrl,'Text','Reset to defaults','ButtonPushedFcn',@(~,~) resetAll());
btn.Layout.Row = row; btn.Layout.Column = [1 2]; row = row + 1;

infoLbl = uilabel(ctrl,'Text','','FontName','Consolas','FontSize',13, ...
    'WordWrap','on','VerticalAlignment','top');
infoLbl.Layout.Row = row; infoLbl.Layout.Column = [1 2];

% Clear frequency ticks for the log axis
fTicks  = [10 20 50 100 200 500 1e3 2e3 5e3 1e4 2e4 5e4 1e5];
fLabels = {'10','20','50','100','200','500','1k','2k','5k','10k','20k','50k','100k'};

update();

% ======================================================================
%  Controls
% ======================================================================
    function r = addControl(r, txt, key, lims, fmt, isLog)
        lb = uilabel(ctrl,'Text',txt);
        lb.Layout.Row = r; lb.Layout.Column = 1;

        ef = uieditfield(ctrl,'numeric','Limits',lims,'Value',p.(key), ...
            'ValueDisplayFormat',fmt,'HorizontalAlignment','right');
        ef.Layout.Row = r; ef.Layout.Column = 2;

        s = uislider(ctrl,'Limits',toSlider(lims,isLog), ...
            'Value',toSlider(p.(key),isLog),'MajorTicks',[],'MinorTicks',[]);
        s.Layout.Row = r + 1; s.Layout.Column = [1 2];

        s.ValueChangingFcn = @(~,e)   fromSlider(key, e.Value,   ef, s, isLog, false); % dragging
        s.ValueChangedFcn  = @(src,~) fromSlider(key, src.Value, ef, s, isLog, true);  % released
        ef.ValueChangedFcn = @(src,~) fromEdit(key, src, s, isLog);                    % typed

        ui.(key) = struct('ef',ef,'s',s,'isLog',isLog);
        r = r + 2;
    end

    function resetAll()
        p = p0;
        keys = fieldnames(ui);
        for i = 1:numel(keys)
            c = ui.(keys{i});
            c.ef.Value = p.(keys{i});
            c.s.Value  = toSlider(p.(keys{i}), c.isLog);
        end
        dd.Value = 'Full-wave';
        cb.Value = true;
        update();
    end

    function sv = toSlider(v, isLog)
        if isLog, sv = log10(v); else, sv = v; end
    end

    function fromSlider(key, sv, ef, s, isLog, released)
        if isLog, v = 10^sv; else, v = sv; end
        v = snapValue(key, v);
        v = min(max(v, ef.Limits(1)), ef.Limits(2));
        changed = (v ~= p.(key));
        p.(key)  = v;
        ef.Value = v;
        if released
            s.Value = toSlider(v, isLog);   % move knob onto the snapped value
        end
        if changed, update(); end           % skip redraws when nothing changed
    end

    function fromEdit(key, ef, s, isLog)
        v = ef.Value;                        % exact value, no snapping
        if strcmp(key,'order'), v = round(v); ef.Value = v; end
        p.(key) = v;
        s.Value = toSlider(v, isLog);
        update();
    end

    function v = snapValue(key, v)
        switch key
            case {'fc','fm','fcut'}          % keep 2 significant digits
                step = max(1, 10^(floor(log10(v)) - 1));
                v = round(v/step) * step;
            case 'm'
                v = round(v*100) / 100;
            case 'snr'
                v = round(v*2) / 2;
            case 'order'
                v = round(v);
        end
    end

    function setOpt(key, v)
        p.(key) = v;
        update();
    end

% ======================================================================
%  Helpers
% ======================================================================
    function s = hz(f)                       % readable frequency text
        if f >= 1000
            s = sprintf('%.2f kHz', f/1000);
        else
            s = sprintf('%.0f Hz', f);
        end
    end

    function HdB = sosGainDB(sos, g, f)      % exact filter gain at frequency f
        zi = exp(-1j*2*pi*f/fs);
        H  = g;
        for k = 1:size(sos,1)
            H = H * (sos(k,1) + sos(k,2)*zi + sos(k,3)*zi^2) / ...
                    (sos(k,4) + sos(k,5)*zi + sos(k,6)*zi^2);
        end
        HdB = 20*log10(abs(H) + 1e-15);
    end

    function [fp, ap] = peakNear(f, A, f0)   % highest bin within +-15% of f0
        band = find(f > 0.85*f0 & f < 1.15*f0);
        if isempty(band)
            [~, band] = min(abs(f - f0));
        end
        [ap, i] = max(A(band));
        fp = f(band(i));
    end

    function marker(ax, x, y, col, shape, txt, yl)
        yy = max(y, yl(1) + 3);              % keep marker visible if below axis
        plot(ax, x, yy, shape, 'MarkerSize',9, 'MarkerFaceColor',col, ...
            'MarkerEdgeColor','k', 'HandleVisibility','off');
        text(ax, x*1.12, yy, txt, 'FontSize',labelSize, 'FontWeight','bold', 'Color','k', ...
            'BackgroundColor',[1 1 1 0.85], 'Margin',1, ...
            'VerticalAlignment','middle', 'Interpreter','tex');
    end

% ======================================================================
%  Simulation and plotting
% ======================================================================
    function update()
        % ---- simulate 6 message periods, show the middle 4 ----
        % The extra period on each side hides filter start-up effects.
        T = min(6/p.fm, 0.3);
        t = 0:1/fs:T;
        N = numel(t);
        show = find(t >= 1/p.fm & t <= 5/p.fm);
        tD = (t(show) - t(show(1))) * 1e3;           % displayed time (ms)

        msg     = cos(2*pi*p.fm*t);
        envTrue = 1 + p.m*msg;                       % the envelope we want back
        x       = envTrue .* sin(2*pi*p.fc*t);       % AM signal

        sigma = sqrt(mean(x.^2) / 10^(p.snr/10));    % noise level from SNR
        xn    = x + sigma*noiseBase(1:N);

        % ---- low-pass filter (second-order sections for stability) ----
        fcut = min(p.fcut, 0.45*fs);
        [z,pl,k] = butter(p.order, fcut/(fs/2));
        [sos,g]  = zp2sos(z,pl,k);
        if p.zeroPhase
            lpf = @(y) filtfilt(sos, g, y);
        else
            lpf = @(y) g*sosfilt(sos, y);
        end

        % ---- detector: rectify + low-pass ----
        if p.fullWave
            rect = abs(xn);   scale = pi/2; ripple = 2*p.fc; rippleSym = '2f_c';
        else
            rect = max(xn,0); scale = pi;   ripple = p.fc;   rippleSym = 'f_c';
        end
        env = lpf(rect) * scale;

        % ---- estimate m: (max - min) / (max + min) ----
        mEst = (max(env(show)) - min(env(show))) / (max(env(show)) + min(env(show)));
        overmod = p.m > 1 + 1e-9;

        % ---- time plot ----
        delete(allchild(ax1)); hold(ax1,'on');   % allchild also catches hidden objects
        plot(ax1, tD, xn(show),      'Color',[.78 .78 .78]);
        plot(ax1, tD, env(show),     'LineWidth',1.8);
        plot(ax1, tD, envTrue(show), 'k--','LineWidth',1.2);
        hold(ax1,'off'); grid(ax1,'on');
        xlim(ax1, [0 tD(end)]);
        xlabel(ax1,'Time (ms)'); ylabel(ax1,'Amplitude');
        legend(ax1, { 'Noisy AM', ...
            sprintf('Detector output  (m_{est} = %.2f)', mEst), ...
            sprintf('True envelope  (m = %.2f)', p.m) }, ...
            'Location','northeastoutside');
        ttl = sprintf('AM signal, m = %.2f, SNR = %.1f dB', p.m, p.snr);
        if overmod, ttl = [ttl '   OVERMODULATED (m > 1)']; end
        title(ax1, ttl);

        % ---- spectrum of rectified signal (Hann window, dB rel. DC) ----
        w   = hann(N).';
        X   = abs(fft(rect .* w)) / sum(w);
        A   = X;  A(2:end) = 2*X(2:end);             % single-sided amplitude
        f   = (0:N-1) * fs / N;
        hk  = 2:floor(N/2);
        AdB = 20*log10(A(hk) / A(1) + 1e-12);        % relative to DC
        fk  = f(hk);

        fh   = logspace(1, log10(fs/2*0.999), 600);   % log-spaced for a smooth curve
        HdBc = arrayfun(@(ff) sosGainDB(sos, g, ff), fh);

        [fmPk, aFm] = peakNear(fk, AdB, p.fm);
        [rpPk, aRp] = peakNear(fk, AdB, ripple);
        gFm  = sosGainDB(sos, g, p.fm);
        gRp  = sosGainDB(sos, g, ripple);
        gCut = sosGainDB(sos, g, fcut);
        if p.zeroPhase                               % filtfilt applies it twice
            gFmEff = 2*gFm; gRpEff = 2*gRp;
        else
            gFmEff = gFm;   gRpEff = gRp;
        end

        yl = [-110 10];
        delete(allchild(ax2)); hold(ax2,'on');   % cla skips hidden markers and lines
        h1 = plot(ax2, fk, AdB, 'Color',[0.30 0.55 0.85]);
        h2 = plot(ax2, fh, HdBc, 'Color',[0.85 0.33 0.10], 'LineWidth',1.8);
        xline(ax2, p.fm,   ':', 'Color',[0 0.5 0],   'HandleVisibility','off');
        xline(ax2, fcut,   '-', 'Color',[0.85 0.33 0.10], 'HandleVisibility','off');
        xline(ax2, ripple, ':', 'Color',[0.6 0 0.6], 'HandleVisibility','off');

        % spectrum peaks (circles)
        marker(ax2, fmPk, aFm, [0 0.7 0], 'o', ...
            sprintf('f_m = %s\n%.1f dB  (20log_{10}m = %.1f)', hz(p.fm), aFm, 20*log10(max(p.m,1e-6))), yl);
        marker(ax2, rpPk, aRp, [0.6 0 0.6], 'o', ...
            sprintf('%s ripple = %s\n%.1f dB', rippleSym, hz(ripple), aRp), yl);

        % filter response points (squares)
        marker(ax2, fcut, gCut, [0.85 0.33 0.10], 's', ...
            sprintf('cutoff = %s\nLPF %.1f dB', hz(fcut), gCut), yl);
        marker(ax2, ripple, gRp, [0.85 0.33 0.10], 's', ...
            sprintf('LPF at %s: %.0f dB', rippleSym, gRp), yl);

        hold(ax2,'off'); grid(ax2,'on');
        ax2.XScale = 'log';
        ax2.XTick = fTicks; ax2.XTickLabel = fLabels;
        ax2.XMinorGrid = 'off';
        xlim(ax2, [10 fs/2]); ylim(ax2, yl);
        xlabel(ax2,'Frequency (Hz)'); ylabel(ax2,'dB');
        title(ax2, 'Rectified signal spectrum (dB rel. DC) with low-pass response');
        legend(ax2, [h1 h2], {'Rectified signal','LPF response'}, 'Location','southwest');

        % ---- readout panel ----
        lines = { sprintf('m set:        %.2f', p.m), ...
                  sprintf('m estimated:  %.2f', mEst), ...
                  '', ...
                  sprintf('f_m peak:     %.1f dB', aFm), ...
                  sprintf('ripple peak:  %.1f dB', aRp), ...
                  sprintf('LPF at fm:    %.1f dB', gFmEff), ...
                  sprintf('LPF at ripple:%.0f dB', gRpEff), ...
                  '', ...
                  sprintf('Shown: %.1f ms (4 periods)', tD(end)), ...
                  sprintf('fs: %.0f kHz', fs/1e3), ''};
        if overmod
            lines{end+1} = '! m > 1: envelope folds, detector cannot recover it';
        end
        if fcut < p.fm
            lines{end+1} = '! Cutoff below fm: envelope is smeared away';
        elseif fcut < 2*p.fm
            lines{end+1} = '! Cutoff close to fm: envelope peaks get attenuated';
        end
        if fcut > ripple/2
            lines{end+1} = '! Cutoff close to ripple: carrier leaks through';
        end
        if p.fc < 10*p.fm
            lines{end+1} = '! fc < 10 x fm: message and carrier hard to separate';
        end
        infoLbl.Text = lines;

        drawnow limitrate;
    end
end
