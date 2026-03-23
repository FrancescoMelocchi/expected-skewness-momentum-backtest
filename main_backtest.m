clc;clear all

% Carica il file Excel
T = readtable("dataset.x.matlab.xlsx",'VariableNamingRule','preserve');

% Trova colonne numeriche assegnando valore 1 a tutte le colonne con
% ticker, 0 a quella delle date
numVars = varfun(@isnumeric, T, 'OutputFormat','uniform'); % vettore logico

% Estrai solo le colonne numeriche, ovvero quelle a cui ho assegnato 1
prezzi = T{:, numVars};

% Pulizia prezzi, elimino valori non validi
prezzi(prezzi <= 0) = NaN;

% filtro penny stocks, escludo titoli con prezzo < 5 all'inizio del mese 
dates_all = T{:,1};
ym_all = year(dates_all)*100 + month(dates_all);
[~, idxFirstMonth] = unique(ym_all, 'first');

% in pratica prima di ogni NaN trovo rendimento 0, la strategia esclude i
% titoli con prezzo mensile<5, subisco una perdita da fallimento solo se il
% titolo ha prezzo>5 a inizio mese e poi fallisce il mese stesso

% traccio esclusioni dovute al filtro, individuando i delisting 
penny_mask = false(size(prezzi));  % stessa dimensione di prezzi

for k = 1:numel(idxFirstMonth)
    startRow = idxFirstMonth(k);
    lowPrice = prezzi(startRow,:) < 5 & ~isnan(prezzi(startRow,:));
    if any(lowPrice)
          % marchia come esclusi per filtro
        prezzi(startRow:end, lowPrice) = NaN;        % escludi da quel mese in avanti
    end
end

% Calcola log-returns giornalieri
logrets = diff(log(prezzi));

% gestione delisting con "rimborso" al prezzo del giorno precedente, se un titolo ha un'ultima quotazione al giorno L e poi sparisce assumiamo "rimborso a prezzo L": settiamo quel log-return = 0 e poi la serie resta NaN.
[nRows, nAssets] = size(prezzi);

for j = 1:nAssets
    p = prezzi(:, j);

    % ultimo giorno con prezzo valido
    last_valid = find(~isnan(p), 1, 'last');

    % se non c'è prezzo o l'ultimo è l'ultima riga, nessun delisting interno alla serie
    if isempty(last_valid) || last_valid == nRows
        continue;
    end

    % primo giorno senza prezzo dopo l'ultimo valido
    delist_day = last_valid + 1;

    % se l'assenza è dovuta al filtro penny, non è un vero delisting e non applico rimborso
    if all(penny_mask(delist_day:end, j))% se tutto il resto della serie è marchiato come penny l'esclusione non è per evento societario
        continue;
    end

    % Imposta log-return L->L+1 = 0 (rimborso a prezzo precedente)
    % logrets ha una riga in meno di prezzi, quindi corrisponde all'indice last_valid
    if last_valid >= 1 && last_valid <= (nRows - 1)
        logrets(last_valid, j) = 0;   % sostituisci eventuale NaN con 0, rendimento pari a 0 equivale a rimborso
    end

    % Dal giorno delisting in poi metti NaN in avanti sui return
    % logrets è lungo nRows-1
    if delist_day <= (nRows - 1)
        logrets(delist_day:end, j) = NaN;
    end
end

% valuto quanti asset in cui ho investito sono effettivamente falliti
nFailedAssets = 0;
failedTickers = {};
failedDates   = {};

for j = 1:nAssets
    p = prezzi(:, j);   % serie dei prezzi per l'asset j
    d = dates_all;      % vettore delle date
    
% Verifico se il titolo è stato investibile almeno una volta
    if all(p <= 5 | isnan(p))
        continue; % mai investibile
    end
    
% Trovo se esiste un momento in cui il prezzo diventa esattamente 0
    idxFail = find(p == 0, 1, 'first');  % prima data di fallimento
    
    if ~isempty(idxFail)
        % Titolo fallito
        nFailedAssets = nFailedAssets + 1;
        failedTickers{end+1} = tickers{j};
        failedDates{end+1}   = d(idxFail); % salvo la data del fallimento
    end
end

% Stampo risultati
fprintf('\nNumero di titoli effettivamente falliti (prezzo>5 e poi=0): %d\n', nFailedAssets);

if nFailedAssets > 0
    disp(table(failedTickers', failedDates', 'VariableNames', {'Ticker','FailDate'}));
end

% Rimuovo eventuali ±Inf o NaN generati
logrets(~isfinite(logrets)) = NaN;


% Estrai le date, shiftate di una riga perché i returns hanno una riga in meno
dates = T{2:end,1};

% Nomi originali dei ticker (colonne numeriche)
tickers = T.Properties.VariableNames(numVars);

% Crea tabella con Date + log-returns
logretTable = array2table(logrets, 'VariableNames', tickers);
logretTable = addvars(logretTable, dates, 'Before', 1, 'NewVariableNames','Date');

%% proxy skewness

skewtab=logretTable(231:end,:); %da riga 231 inizia il primo mese di analisi della skewness
% questo skip di 11 mesi è dovuto al metodo del calcolo del momentum, il
% quale considera una rolling window di 12 mesi + un mese di skip

% associo ad ogni giorno un mese specifico
ys = year(skewtab.Date)*100 + month(skewtab.Date);
[ngg, NomiGruppi] = findgroups(ys);

maxrendmens = splitapply(@max, skewtab{:,2:end}, ngg); %tabella con i rendimenti gg massimi del mese
%trovo il rendimento massimo mensile, ovvero la skewness

% risultato in tabella
datemens = splitapply(@(x) x(1), skewtab.Date, ngg);

% creo la tabella finale direttamente con ticker come intestazioni
skewmens = array2table(maxrendmens, 'VariableNames', tickers);

% Aggiungo Date e MonthID di misura (mese t-1)
skewmens = addvars(skewmens, datemens, NomiGruppi,'Before',1,'NewVariableNames',{'Date','MonthID_measure'});
% Sposto la skewness al mese successivo (mese t di holding), in quanto essa viene calcolata utilizzando i dati del mese precedente

holdDates = dateshift(datemens,'start','month','next');
skewmens.MonthID = year(holdDates)*100 + month(holdDates);

% Rimuovo variabili non ticker e metto MonthID come prima colonna
skewmens = removevars(skewmens, {'Date','MonthID_measure'});
skewmens = skewmens(:, [{'MonthID'}, tickers]);


%% proxy momentum, calcolo logrendimenti mensili
ym = year(logretTable.Date)*100 + month(logretTable.Date);
[nmesi, ~] = findgroups(ym);

unique_dates = splitapply(@(x) x(end), logretTable.Date, nmesi);% vettore di date mensili con gg

%matrice di rendimenti logaritmici mensili dal 2006
rets_log_monthly = splitapply(@sum, logretTable{:,2:end}, nmesi);

%pulisco matrice precedente eliminando dati 2006 e aggiungo ticker e date
monthly_log = array2table(rets_log_monthly,'VariableNames', logretTable.Properties.VariableNames(2:end));
monthly_log = addvars(monthly_log, unique_dates, 'Before', 1, 'NewVariableNames', "Date");


%calcolo del momentum
Wstandeq = 11;   % mesi inclusi (12–2 usa 11 mesi)
K = 1;    % mesi saltati (salta l'ultimo mese)

dates_monthly = monthly_log.Date;
retsM = monthly_log{:,2:end};     % matrice rendimenti log mensili T×N
[nObs, nAssets] = size(retsM);

momentum = nan(nObs, nAssets); % inizializzazione matrice 

for t = (Wstandeq + K + 1):nObs
    startIdx = t - (Wstandeq + K);       % = t-12  se W=11, K=1
    stopIdx  = t - (K + 1);       % = t-2   se W=11, K=1
    momentum(t,:) = sum(retsM(startIdx:stopIdx, :), 1); % considero gli ultimi 12 mesi ma salto l'ultimo
end

%creazione tabella momentum con MonthID e ticker
momentumTable = array2table(momentum, 'VariableNames', monthly_log.Properties.VariableNames(2:end));
momentumTable = addvars(momentumTable, dates_monthly, 'Before', 1, 'NewVariableNames','Date');

% pulisco la tabella eliminando il primo anno di raccolta dati dove ho solo NaN
momentumTable=momentumTable(12:end,:);
% crea MonthID dentro momentumTable
momentumTable.MonthID = year(momentumTable.Date)*100 + month(momentumTable.Date);
% metti MonthID come prima colonna e rimuovi le date
momentumTable = movevars(momentumTable,'MonthID','Before','Date');
momentumTable.Date = [];

%% Allineamento date comuni tra skewness, momentum e rendimenti

moID_monthly = year(monthly_log.Date)*100 + month(monthly_log.Date);
momID = momentumTable.MonthID;
skewID = skewmens.MonthID;

commonID = intersect(moID_monthly, intersect(momID, skewID));

[~,locM]   = ismember(commonID, moID_monthly);
[~,locMom] = ismember(commonID, momID);
[~,locSk]  = ismember(commonID, skewID);

% allineamento tabelle, parto dagli stessi MonthID, in mothly_log abbiamo le date, si parte da gennaio 2007
monthly_log   = monthly_log(locM, :);
momentumTable = momentumTable(locMom, :);
skewmens  = skewmens(locSk, :);


%% Controllo coerenza colonne tra skewness e momentum

if ~isequal(skewmens.Properties.VariableNames(2:end), momentumTable.Properties.VariableNames(2:end))
    error('I ticker di skewmens e momentumTable non coincidono per nome/ordine.');
end

%Calcolo dei quintili della skewness (proxy = max rendimento mensile)

% Estraggo MonthID e skewness per i titoli
monthIDs = skewmens.MonthID;
skewVals = skewmens{:, 2:end};  % senza MonthID e ticker

% Numero di mesi e numero di titoli
[nMesi, nAssets] = size(skewVals);

% Preallocazione: matrice con quintile di appartenenza per ogni titolo e mese
quintili = nan(nMesi, nAssets);

% Loop sui mesi
for t = 1:nMesi
    valori = skewVals(t, :);     % skewness dei titoli nel mese t
    
    % Calcolo soglie dei quintili (escludo eventuali NaN)
    soglie = quantile(valori(~isnan(valori)), [0.2 0.4 0.6 0.8]);
    
    % Assegno quintile in base alle soglie
    for j = 1:nAssets
        if isnan(valori(j))
            quintili(t,j) = NaN; % se manca dato, resta NaN
        elseif valori(j) <= soglie(1)
            quintili(t,j) = 1;
        elseif valori(j) <= soglie(2)
            quintili(t,j) = 2;
        elseif valori(j) <= soglie(3)
            quintili(t,j) = 3;
        elseif valori(j) <= soglie(4)
            quintili(t,j) = 4;
        else
            quintili(t,j) = 5;
        end
    end
end

% Tabella con MonthID, ticker + quintile per ogni titolo
quintileskewTable = array2table(quintili, 'VariableNames', skewmens.Properties.VariableNames(2:end));
quintileskewTable = addvars(quintileskewTable, monthIDs, 'Before', 1, 'NewVariableNames','MonthID');

%% Doppio sorting: prima quintili di skewness e poi quelli di momentum considerando una disribuzione diversa per ogni quintile

% Estraggo i valori di momentum (stessa struttura di skewmens)
momVals = momentumTable{:,2:end};   % senza MonthID
momMonthIDs = momentumTable.MonthID;

% Controllo che MonthID coincidano (skewmens e momentumTable)
if ~isequal(monthIDs, momMonthIDs)
    error('I MonthID di skewness e momentum non coincidono. Verifica gli allineamenti.');
end

% Preallocazione: matrice per quintili di momentum condizionati alla skewness
momQ = nan(nMesi, nAssets);

% Loop sui mesi
for t = 1:nMesi
    % prendo quintili skewness di quel mese 
    skewGroups = quintili(t,:);    % 1–5 oppure NaN
    momValues  = momVals(t,:);     % momentum corrispondente
    
    % ciclo sui 5 quintili di skewness
    for q = 1:5
        idx = (skewGroups == q);   % quali titoli appartengono a skewness quintile q
        if sum(idx) >= 5           % servono almeno 5 titoli per fare quintili
            vals = momValues(idx);
            
            % Calcolo soglie dei quintili di momentum in questo sottogruppo
            soglieMom = quantile(vals(~isnan(vals)), [0.2 0.4 0.6 0.8]);
            
            % Assegno quintile di momentum dentro il gruppo skewness=q
            tmp = nan(size(vals));
            for j = 1:length(vals)
                if isnan(vals(j))
                    tmp(j) = NaN;
                elseif vals(j) <= soglieMom(1)
                    tmp(j) = 1;
                elseif vals(j) <= soglieMom(2)
                    tmp(j) = 2;
                elseif vals(j) <= soglieMom(3)
                    tmp(j) = 3;
                elseif vals(j) <= soglieMom(4)
                    tmp(j) = 4;
                else
                    tmp(j) = 5;
                end
            end
            % salvo nei risultati globali
            momQ(t, idx) = tmp;
        end
    end
end

% Tabella finale con MonthID + quintili skewness + quintili
% momentum(skew.mom)
quintileMomentumTable = array2table(momQ,'VariableNames', skewmens.Properties.VariableNames(2:end));
quintileMomentumTable = addvars(quintileMomentumTable, monthIDs, 'Before', 1, 'NewVariableNames','MonthID');

%% pulizia matrici momentum skewness, da utilizzare per ogni portafoglio

%retsM è la matrice dei rendimenti, dal 1/2007 in poi, come le altrematrici
% Estrai le matrici dei quintili (senza MonthID)
skewQ = quintileskewTable{:, 2:end};          % T x N matrice quintili skewness
momQ  = quintileMomentumTable{:, 2:end};      % T x N matrice quintili momentum(ricalcolato per comodità)
monthIDs = quintileskewTable.MonthID;         % T x 1 vettore MonthId

% Allinea monthly_log ai MonthID usati da skew/momentum
moID_monthly = year(monthly_log.Date)*100 + month(monthly_log.Date);

%% creazione matrice pesi portafoglio standard e controllo logica zero-investment

colsMonthly   = monthly_log.Properties.VariableNames(2:end); %riga ticker rendimenti mensili
colsExpected  = quintileskewTable.Properties.VariableNames(2:end); %riga ticker skewness
if ~isequal(colsMonthly, colsExpected)
    % riordino monthly_log per avere la stessa sequenza di tickers
    monthly_log = monthly_log(:, [{'Date'}, colsExpected]);
end

[tf, loc] = ismember(monthIDs, moID_monthly);
if ~all(tf)
    error('Monthly_log non copre tutti i MonthID dei quintili. Verifica l''allineamento delle date.');
end

% Matrice dei log-rendimenti mensili T x N (allineata a skew/momentum)
retsM = monthly_log{loc, 2:end};   % T x N matrice rendimenti eliminando i primi mesi di analisi
[nMesi, nAssets] = size(retsM);

% Matrice dei pesi T x N (zero-investment: +0,5 sui long, -0,5 sugli short)
Wstandeq = zeros(nMesi, nAssets);

for t = 1:nMesi
    % consideriamo solo gli asset in skewness Q3
    idx_skew3 = (skewQ(t, :) == 3);

    % long = winners (momQ=5) dentro skewQ=3
    idxW = idx_skew3 & (momQ(t, :) == 5);
    % short = losers (momQ=1) dentro skewQ=3
    idxL = idx_skew3 & (momQ(t, :) == 1);

    nW = sum(idxW);
    nL = sum(idxL);
    
    % pesi stabiliti in logica equally-weighted
    if nW > 0 && nL > 0
        Wstandeq(t, idxW) =  0.5 / nW;   % long: somma +10
        Wstandeq(t, idxL) = -0.5 / nL;   % short: somma -10
    end
end

%  retsM : T x N log-rendimenti mensili allineati
%  Wstand    : T x N pesi long/short per la strategia benchmark 

% Controllo zero-investment su ogni mese
tol = 1e-10;                      % tolleranza numerica, molto piccola
isZeroInvest = true(nMesi,1);     % true = ok, false = non zero-investment

for t = 1:nMesi
    sommaPesi = sum(Wstandeq(t,:));      % somma pesi del mese t
    if abs(sommaPesi) > tol
        isZeroInvest(t) = false;  % non è zero-investment
        warning('Mese %d (MonthID=%d): somma pesi = %.6f (NON zero-investment)',t, monthIDs(t), sommaPesi);
    end
end

% Riepilogo
fprintf('\nCheck zero-investment completato:\n');
fprintf(' - Mesi totali: %d\n', nMesi);
fprintf(' - Mesi OK    : %d\n', sum(isZeroInvest));
fprintf(' - Mesi FAIL  : %d\n', sum(~isZeroInvest));

%% calcolo matrice pesi per portafoglio weakended e controllo logica zero invested
Wweakenedeq = zeros(nMesi, nAssets);

for t = 1:nMesi
    % Long: skew=5 & mom=5
    idxW = (skewQ(t, :) == 5) & (momQ(t, :) == 5);
    % Short: skew=1 & mom=1
    idxL = (skewQ(t, :) == 1) & (momQ(t, :) == 1);

    nW = sum(idxW);
    nL = sum(idxL);

    if nW > 0 && nL > 0
        % equally weighted long/short, normalizzati a ±0.5
        Wweakenedeq(t, idxW) =  0.5 / nW;
        Wweakenedeq(t, idxL) = -0.5 / nL;
    end
end

% Controllo zero-investment
tol = 1e-10;
isZeroInvest_weakened = true(nMesi,1);

for t = 1:nMesi
    sommaPesi = sum(Wweakenedeq(t,:));
    if abs(sommaPesi) > tol
        isZeroInvest_weakened(t) = false;
        warning('Weakened: Mese %d (MonthID=%d) NON zero-investment (somma pesi = %.6f)',t, monthIDs(t), sommaPesi);
    end
end

% Riepilogo
fprintf('\nCheck zero-investment portafoglio WEAKENED:\n');
fprintf(' - Mesi totali: %d\n', nMesi);
fprintf(' - Mesi OK    : %d\n', sum(isZeroInvest_weakened));
fprintf(' - Mesi FAIL  : %d\n', sum(~isZeroInvest_weakened));

%% calcolo matrice pesi per portafoglio enhanced e controllo logica zero invested

Wenhancedeq = zeros(nMesi, nAssets);

for t = 1:nMesi
    % Long: skew=1 & mom=5
    idxW = (skewQ(t, :) == 1) & (momQ(t, :) == 5);
    % Short: skew=5 & mom=1
    idxL = (skewQ(t, :) == 5) & (momQ(t, :) == 1);

    nW = sum(idxW);
    nL = sum(idxL);

    if nW > 0 && nL > 0
        % equally weighted long/short, normalizzati a ±0.5
        Wenhancedeq(t, idxW) =  0.5 / nW;
        Wenhancedeq(t, idxL) = -0.5 / nL;
    end
end

% Controllo zero-investment
tol = 1e-10;
isZeroInvest_enhanced = true(nMesi,1);

for t = 1:nMesi
    sommaPesi = sum(Wenhancedeq(t,:));
    if abs(sommaPesi) > tol
        isZeroInvest_enhanced(t) = false;
        warning('Enhanced: Mese %d (MonthID=%d) NON zero-investment (somma pesi = %.6f)',t, monthIDs(t), sommaPesi);
    end
end

% Riepilogo
fprintf('\nCheck zero-investment portafoglio ENHANCED:\n');
fprintf(' - Mesi totali: %d\n', nMesi);
fprintf(' - Mesi OK    : %d\n', sum(isZeroInvest_enhanced));
fprintf(' - Mesi FAIL  : %d\n', sum(~isZeroInvest_enhanced));

%% calcolo rendimenti portafogli std weak enhan

% Rimpiazzo NaN con 0 nei rendimenti per evitare contaminazioni
retsM_filled = retsM;
retsM_filled(isnan(retsM_filled)) = 0; % tale semplificazione è valida poichè gli asset falliti su cui ho investito sono 0, i titoli con NaN sono tutti dovuti a delisting=rimborso

% Calcolo rendimenti portafogli
ret_port_std     = sum(Wstandeq   .* retsM_filled, 2);
ret_port_weak    = sum(Wweakenedeq.* retsM_filled, 2);
ret_port_enh     = sum(Wenhancedeq.* retsM_filled, 2);

% Portafoglio Momentum-neutral
ret_port_mn = ret_port_enh - ret_port_weak;
Wneutreq=Wenhancedeq-Wweakenedeq;


%% costruzione EQUITY LINES

% Capitale iniziale
initial_capital = 100;

% dato che i rendimenti sono log:
equity_std = initial_capital * exp(cumsum(ret_port_std));
equity_weak = initial_capital * exp(cumsum(ret_port_weak));
equity_enh = initial_capital * exp(cumsum(ret_port_enh));
equity_mn  = initial_capital * exp(cumsum(ret_port_mn));

% costruisco vettore date
dates_axis = monthly_log.Date;   % già allineato ai rendimenti

% creo plot separati
figure;
subplot(2,2,1)
plot(dates_axis, equity_std,'LineWidth',1.5), grid on
datetick('x','yyyy')
title('Equity Line - Portafoglio STD')
ylabel('Capitale')

subplot(2,2,2)
plot(dates_axis, equity_weak,'LineWidth',1.5), grid on
datetick('x','yyyy')
title('Equity Line - Portafoglio WEAKENED')
ylabel('Capitale')

subplot(2,2,3)
plot(dates_axis, equity_enh,'LineWidth',1.5), grid on
datetick('x','yyyy')
title('Equity Line - Portafoglio ENHANCED')
ylabel('Capitale')

subplot(2,2,4)
plot(dates_axis, equity_mn,'LineWidth',1.5), grid on
datetick('x','yyyy')
title('Equity Line - Portafoglio MOMENTUM-NEUTRAL')
ylabel('Capitale')

% plot comparativo
figure('Color',[1 1 1]); % sfondo finestra bianco
ax = gca; 
ax.Color = [1 1 1];      % sfondo area del grafico bianco

plot(dates_axis, equity_std,'LineWidth',1.5); hold on
plot(dates_axis, equity_weak,'LineWidth',1.5);
plot(dates_axis, equity_enh,'LineWidth',1.5);
plot(dates_axis, equity_mn,'LineWidth',1.5);
grid on
datetick('x','yyyy')
legend('STD','WEAKENED','ENHANCED','MOMENTUM-NEUTRAL','Location','best')
title('Equity Line')
ylabel('Capitale investito')
xlabel('Anno')

%% Calcolo daily dei portafogli e Barroso–Santa-Clara 

% Parametri
target_vol_ann = 0.13;    % volatilità target annuale
window_months  = 12;      % finestra rolling di 12 mesi
alpha_down     = 0.5;     % scaling nei down-market
q_vol_thresh   = 0.75;    % soglia quantile volatilità per regime DM

% Calcolo volatilità mensile con rolling window
vol_std  = movstd(ret_port_std,  [window_months-1 0], 'omitnan');
vol_weak = movstd(ret_port_weak, [window_months-1 0], 'omitnan');
vol_enh  = movstd(ret_port_enh,  [window_months-1 0], 'omitnan');
vol_mn   = movstd(ret_port_mn,   [window_months-1 0], 'omitnan');

% volatilità target mensile
target_vol_m = target_vol_ann / sqrt(12);

% Calcolo leva BSC 
lev_std  = target_vol_m ./ max(vol_std,  eps);
lev_weak = target_vol_m ./ max(vol_weak, eps);
lev_enh  = target_vol_m ./ max(vol_enh,  eps);
lev_mn   = target_vol_m ./ max(vol_mn,   eps);

% limite minimo e massimo leva (0 - 3)
lev_std  = min(max(lev_std,  0), 3);
lev_weak = min(max(lev_weak, 0), 3);
lev_enh  = min(max(lev_enh,  0), 3);
lev_mn   = min(max(lev_mn,   0), 3);

% shift leva di 1 mese 
lev_std  = [1; lev_std(1:end-1)];
lev_weak = [1; lev_weak(1:end-1)];
lev_enh  = [1; lev_enh(1:end-1)];
lev_mn   = [1; lev_mn(1:end-1)];

% Rendimenti con volatility targeting di BSC 
ret_port_std_BSC  = lev_std  .* ret_port_std;
ret_port_weak_BSC = lev_weak .* ret_port_weak;
ret_port_enh_BSC  = lev_enh  .* ret_port_enh;
ret_port_mn_BSC   = lev_mn   .* ret_port_mn;

% equity line BSC 
initial_capital = 100;

equity_std_BSC  = initial_capital * exp(cumsum(ret_port_std_BSC));
equity_weak_BSC = initial_capital * exp(cumsum(ret_port_weak_BSC));
equity_enh_BSC  = initial_capital * exp(cumsum(ret_port_enh_BSC));
equity_mn_BSC   = initial_capital * exp(cumsum(ret_port_mn_BSC));

% plot Equity Line regola BSC 
col_STD = [0 0.4470 0.7410];
col_WEA = [0.8500 0.3250 0.0980];
col_ENH = [0.9290 0.6940 0.1250];
col_MN  = [0.4940 0.1840 0.5560];

figure('Color','w'); hold on;
plot(dates_axis, equity_std_BSC,  'Color', col_STD, 'LineWidth', 1.5);
plot(dates_axis, equity_weak_BSC, 'Color', col_WEA, 'LineWidth', 1.5);
plot(dates_axis, equity_enh_BSC,  'Color', col_ENH, 'LineWidth', 1.8);
plot(dates_axis, equity_mn_BSC,   'Color', col_MN,  'LineWidth', 1.5);

grid on; datetick('x','yyyy');
xlabel('Anno'); ylabel('Capitale Investito');
title('Equity Line – Strategie con regola Barroso–Santa Clara (BSC)');
legend('STD BSC','WEAKENED BSC','ENHANCED BSC','MOMENTUM-NEUTRAL BSC','Location','best');

ax = gca;                         % prendi l'asse corrente
ax.LineWidth = 1.0;               % spessore dei bordi del grafico
ax.FontSize = 9;                 % ingrandisci font per maggiore leggibilità
box on;                           % assicura che il box sia disegnato intorno al grafico




%% Regola Daniel e Moskowitz 
% l'obiettivo è di ridurre l'esposizione nei regimi in cui il momentum storicamente fallisce combinando drawdown cumulato e volatilità di mercato

% Calcolo rendimento medio del mercato da utilizzare come proxy
mkt_ret = mean(retsM, 2, 'omitnan');  % media dell'universo

% Calcolo drawdown cumulato a 24 mesi
window_dd = 24;
mkt_cum24 = movsum(mkt_ret, [window_dd-1 0], 'omitnan');
mkt_cum24 = [NaN(window_dd-1,1); mkt_cum24(window_dd:end)];

% Calcolo volatilità rolling a 12 mesi 
vol_window = 12;
vol_mkt = movstd(mkt_ret, [vol_window-1 0], 'omitnan');

% Calcolo soglia di alta volatilità (75° percentile)
vol_mkt_valid = vol_mkt(isfinite(vol_mkt));
vol_thresh = quantile(vol_mkt_valid(:), 0.75);

% Identificazione dei regimi critici 
isDown    = mkt_cum24 < 0;        % mercato in drawdown cumulato
isHighVol = vol_mkt > vol_thresh; % regime di alta volatilità

% Regime pericoloso se almeno una delle due condizioni è vera
risk_flag = isDown | isHighVol;

% Calcolo coefficiente di scaling dinamico 

% scaling legato all'intensità del drawdown limite massimo a -30%
drawdown_norm = max(mkt_cum24, -0.30);
scale_dd = 1 + (drawdown_norm / 0.30);  % da 0.7, in caso di forte drawdown, a 1

% aggiustamento legato all'eccesso di volatilità
vol_ratio = vol_mkt ./ vol_thresh;
vol_ratio(vol_ratio < 1) = 1;
scale_vol = 1 ./ min(vol_ratio, 1.5);   % massimo =0.67

% coefficiente finale combinato
k_DM = scale_dd .* scale_vol;
k_DM(~risk_flag) = 1; % se non si prevedono crolli futuri, nessun aggiustamento

% Shift di 1 mese per evitare look-ahead bias
k_DM = [1; k_DM(1:end-1)];

% Rendimenti con la regola DM 
ret_port_std_DM  = ret_port_std  .* k_DM;
ret_port_weak_DM = ret_port_weak .* k_DM;
ret_port_enh_DM  = ret_port_enh  .* k_DM;
ret_port_mn_DM   = ret_port_mn   .* k_DM;

% Equity line solo DM 
equity_std_DM  = initial_capital * exp(cumsum(ret_port_std_DM));
equity_weak_DM = initial_capital * exp(cumsum(ret_port_weak_DM));
equity_enh_DM  = initial_capital * exp(cumsum(ret_port_enh_DM));
equity_mn_DM   = initial_capital * exp(cumsum(ret_port_mn_DM));

%% Applicazione DM + BSC 
% Applico la regola di Barroso–Santa Clara dopo la regola DM
% Calcolo volatilità rolling sui rendimenti già scalati con DM
window_months = 12;
target_vol_ann = 0.13;
target_vol_m = target_vol_ann / sqrt(12);

vol_std_DM  = movstd(ret_port_std_DM,  [window_months-1 0], 'omitnan');
vol_weak_DM = movstd(ret_port_weak_DM, [window_months-1 0], 'omitnan');
vol_enh_DM  = movstd(ret_port_enh_DM,  [window_months-1 0], 'omitnan');
vol_mn_DM   = movstd(ret_port_mn_DM,   [window_months-1 0], 'omitnan');

% Calcolo leva BSC sui rendimenti DM (e non su quelli originali)
lev_std_DM  = target_vol_m ./ max(vol_std_DM, eps);
lev_weak_DM = target_vol_m ./ max(vol_weak_DM, eps);
lev_enh_DM  = target_vol_m ./ max(vol_enh_DM, eps);
lev_mn_DM   = target_vol_m ./ max(vol_mn_DM, eps);

% Limita la leva tra 0 e 3 per evitare esplosioni
lev_std_DM  = min(max(lev_std_DM, 0), 3);
lev_weak_DM = min(max(lev_weak_DM, 0), 3);
lev_enh_DM  = min(max(lev_enh_DM, 0), 3);
lev_mn_DM   = min(max(lev_mn_DM, 0), 3);

% Shift di 1 mese per evitare look-ahead bias con leva calcolata prima
lev_std_DM  = [1; lev_std_DM(1:end-1)];
lev_weak_DM = [1; lev_weak_DM(1:end-1)];
lev_enh_DM  = [1; lev_enh_DM(1:end-1)];
lev_mn_DM   = [1; lev_mn_DM(1:end-1)];

% Rendimenti finali con entrambe le regole applicate nel giusto ordine
ret_port_std_DM_BSC  = lev_std_DM  .* ret_port_std_DM;
ret_port_weak_DM_BSC = lev_weak_DM .* ret_port_weak_DM;
ret_port_enh_DM_BSC  = lev_enh_DM  .* ret_port_enh_DM;
ret_port_mn_DM_BSC   = lev_mn_DM   .* ret_port_mn_DM;

% Equity line DM + BSC
initial_capital = 100;
equity_std_DM_BSC  = initial_capital * exp(cumsum(ret_port_std_DM_BSC));
equity_weak_DM_BSC = initial_capital * exp(cumsum(ret_port_weak_DM_BSC));
equity_enh_DM_BSC  = initial_capital * exp(cumsum(ret_port_enh_DM_BSC));
equity_mn_DM_BSC   = initial_capital * exp(cumsum(ret_port_mn_DM_BSC));


%% plot dei risultati DM e DM+BSC

col_STD = [0 0.4470 0.7410];
col_WEA = [0.8500 0.3250 0.0980];
col_ENH = [0.9290 0.6940 0.1250];
col_MN  = [0.4940 0.1840 0.5560];

% Solo DM 
figure('Color','w'); hold on;
plot(dates_axis, equity_std_DM,  'Color', col_STD, 'LineWidth', 1.5);
plot(dates_axis, equity_weak_DM, 'Color', col_WEA, 'LineWidth', 1.5);
plot(dates_axis, equity_enh_DM,  'Color', col_ENH, 'LineWidth', 1.8);
plot(dates_axis, equity_mn_DM,   'Color', col_MN,  'LineWidth', 1.5);
grid on; datetick('x','yyyy');
xlabel('Anno'); ylabel('Capitale Investito');
title('Equity Line – Strategie con regola Daniel–Moskowitz (DM)');
legend('STD DM','WEAKENED DM','ENHANCED DM','MOMENTUM-NEUTRAL DM','Location','best');

ax = gca;                         % prendi l'asse corrente
ax.LineWidth = 1.0;               % spessore dei bordi del grafico
ax.FontSize = 9;                 % ingrandisci font per maggiore leggibilità
box on;                           % assicura che il box sia disegnato intorno al grafico


% DM + BSC
figure('Color','w'); hold on;
plot(dates_axis, equity_std_DM_BSC,  'Color', col_STD, 'LineWidth', 1.5);
plot(dates_axis, equity_weak_DM_BSC, 'Color', col_WEA, 'LineWidth', 1.5);
plot(dates_axis, equity_enh_DM_BSC,  'Color', col_ENH, 'LineWidth', 1.8);
plot(dates_axis, equity_mn_DM_BSC,   'Color', col_MN,  'LineWidth', 1.5);
grid on; datetick('x','yyyy');
xlabel('Anno'); ylabel('Capitale Investito');
title('Equity Line – Strategie con regole BSC e DM');
legend('STD DM+BSC','WEAKENED DM+BSC','ENHANCED DM+BSC','MOMENTUM-NEUTRAL DM+BSC','Location','best');


ax = gca;                         % prendi l'asse corrente
ax.LineWidth = 1.0;               % spessore dei bordi del grafico
ax.FontSize = 9;                 % ingrandisci font per maggiore leggibilità
box on;                           % assicura che il box sia disegnato intorno al grafico




%% Regressione Fama–French 

% Carica fattori Fama-French
FF = readtable("Fattori.FamaFrench.xlsx",'PreserveVariableNames',true);

% Conversione e normalizzazione date 
FF.Date = datetime(FF.Date,'InputFormat','dd-MMM-yyyy');
FF.Date = dateshift(FF.Date,'end','month');

% Seleziono colonne utili
keepVars = {'Date','Mkt-RF','SMB','HML','RMW','CMA','RF'};
FF = FF(:, keepVars);

% Allineamento date strategie 
dates_axis = dateshift(monthly_log.Date,'end','month');   % date delle strategie 
[tf_rf, idx_rf] = ismember(dates_axis, FF.Date);

if ~all(tf_rf)
    warning('Alcune date delle strategie non trovano corrispondenza nei fattori FF. Verranno eliminate.');
end

% Allineamento completo
valid_idx = tf_rf;
dates_axis = dates_axis(valid_idx);
FF = FF(idx_rf(valid_idx), :);

% Calcolo rendimenti semplici e in eccesso

% Converte tutti i log-rendimenti mensili delle strategie in semplici
log2simple = @(rlog) exp(rlog) - 1;

r_std_simple        = log2simple(ret_port_std(valid_idx));
r_weak_simple       = log2simple(ret_port_weak(valid_idx));
r_enh_simple        = log2simple(ret_port_enh(valid_idx));
r_mn_simple         = log2simple(ret_port_mn(valid_idx));

r_std_DM_BSC_simple   = log2simple(ret_port_std_DM_BSC(valid_idx));
r_weak_DM_BSC_simple  = log2simple(ret_port_weak_DM_BSC(valid_idx));
r_enh_DM_BSC_simple   = log2simple(ret_port_enh_DM_BSC(valid_idx));
r_mn_DM_BSC_simple    = log2simple(ret_port_mn_DM_BSC(valid_idx));

% Risk-free mensile allineato
rf_simple = FF.RF;

% Rendimenti semplici in eccesso 
ret_port_std_exc= r_std_simple        - rf_simple;
ret_port_weak_exc= r_weak_simple       - rf_simple;
ret_port_enh_exc= r_enh_simple        - rf_simple;
ret_port_mn_exc= r_mn_simple         - rf_simple;

ret_port_std_DM_BSC_exc= r_std_DM_BSC_simple   - rf_simple;
ret_port_weak_DM_BSC_exc= r_weak_DM_BSC_simple  - rf_simple;
ret_port_enh_DM_BSC_exc= r_enh_DM_BSC_simple   - rf_simple;
ret_port_mn_DM_BSC_exc= r_mn_DM_BSC_simple    - rf_simple;

% Matrice dei fattori 
MF = FF{:, {'Mkt-RF','SMB','HML','RMW','CMA'}};

% Regressioni OLS 

strategies = {
    'STD',          ret_port_std_exc;
    'WEAKENED',     ret_port_weak_exc;
    'ENHANCED',     ret_port_enh_exc;
    'NEUTRAL',      ret_port_mn_exc;
    'STD_DM_BSC',      ret_port_std_DM_BSC_exc;
    'WEAKENED_DM_BSC', ret_port_weak_DM_BSC_exc;
    'ENHANCED_DM_BSC', ret_port_enh_DM_BSC_exc;
    'NEUTRAL_DM_BSC',  ret_port_mn_DM_BSC_exc;
};

results = struct();

for i = 1:size(strategies,1)
    name = strategies{i,1};
    Y    = strategies{i,2};
    
    % Aggiungi costante
    X = [ones(size(MF,1),1), MF];
    
    % Stima OLS
    coeffs = X \ Y;
    Y_hat  = X * coeffs;
    resid  = Y - Y_hat;
    
    % Stima varianza residui e SE
    sigma2 = var(resid,'omitnan');
    covB   = sigma2 * inv(X' * X);
    se     = sqrt(diag(covB));
    
    % Salvataggio risultati
    results.(name).alpha        = coeffs(1);
    results.(name).betas        = coeffs(2:end);
    results.(name).tstat_alpha  = coeffs(1) / se(1);
    results.(name).alpha_ann    = (1 + coeffs(1))^12 - 1;
    results.(name).R2           = 1 - var(resid,'omitnan')/var(Y,'omitnan');
end

% Tabella 
names = fieldnames(results);
summary = table('Size',[numel(names) 9],'VariableTypes',repmat("double",1,9),'VariableNames',{'Alpha','Alpha_ann','tAlpha','Beta_MKT','Beta_SMB','Beta_HML','Beta_RMW','Beta_CMA','R2'},'RowNames',names);

for i = 1:numel(names)
    r = results.(names{i});
    summary{i,:} = [r.alpha, r.alpha_ann, r.tstat_alpha, r.betas', r.R2];
end

disp(' ');
disp('Coefficienti Fama–French');
disp(summary);


%% costruzione portfolio equally weighted per metrica omega costruita

% Copia dei prezzi già puliti da penny stocks
P_bench = prezzi;

% Gestione delisting, sostituisco con NaN dal giorno successivo all'ultima quotazione
[nRows, nAssets] = size(P_bench);
for j = 1:nAssets
    p = P_bench(:, j);
    if all(isnan(p))
        continue;
    end
    last_valid = find(~isnan(p), 1, 'last');
    if ~isempty(last_valid) && last_valid < nRows
        p(last_valid+1:end) = NaN;
    end
    P_bench(:, j) = p;
end

% Calcolo log-rendimenti giornalieri
logrets_bench = diff(log(P_bench));
dates_all = T{2:end,1};

% Allineamento dimensioni di sicurezza
if size(logrets_bench,1) ~= numel(dates_all)
    minLen = min(size(logrets_bench,1), numel(dates_all));
    logrets_bench = logrets_bench(1:minLen,:);
    dates_all = dates_all(1:minLen);
end

% Conversione a rendimenti semplici giornalieri, necessario per evitare bias
rets_simple_daily = exp(logrets_bench) - 1;

% Calcolo rendimento equally-weighted giornaliero
ret_bench_daily = nanmean(rets_simple_daily, 2);

% Conversione a rendimenti mensili semplici
ym_all = year(dates_all)*100 + month(dates_all);
unique_months = unique(ym_all);
nMonths = numel(unique_months);
rets_bench_monthly = nan(nMonths,1);

for m = 1:nMonths
    mask = (ym_all == unique_months(m));
    r_month = ret_bench_daily(mask);
    rets_bench_monthly(m) = prod(1 + r_month, 'omitnan') - 1; % prodotto cumulato
end

% Equity line benchmark
initial_capital = 100;
equity_bench = initial_capital * cumprod(1 + rets_bench_monthly, 'omitnan');

% Date mensili di riferimento 
dates_bench = arrayfun(@(x) dateshift(datetime(floor(x/100), mod(x,100), 1), 'end', 'month'), unique_months);

% Plot del benchmark
figure('Color','w');
plot(dates_bench, equity_bench, 'k', 'LineWidth', 1.8);
grid on; datetick('x','yyyy','keeplimits');
title('Equity Line – Benchmark Equally Weighted');
ylabel('Capitale investito');
xlabel('Anno');

% Statistiche base benchmark
mean_month_ret = 100 * mean(rets_bench_monthly, 'omitnan');
vol_month_ret  = 100 * std(rets_bench_monthly, 'omitnan');
fprintf('Rendimento medio mensile (benchmark): %.4f%%\n', mean_month_ret);
fprintf('Volatilità mensile (benchmark): %.4f%%\n', vol_month_ret);


%% Metriche di performance coerenti con log-returns

% Usa direttamente i log-returns cumulati dei portafogli
log2simple = @(rlog) exp(rlog) - 1;

% Calcola rendimenti semplici coerenti dai log-returns originali
r_std      = log2simple(ret_port_std);
r_weak     = log2simple(ret_port_weak);
r_enh      = log2simple(ret_port_enh);
r_mn       = log2simple(ret_port_mn);

r_std_BSC  = log2simple(ret_port_std_BSC);
r_weak_BSC = log2simple(ret_port_weak_BSC);
r_enh_BSC  = log2simple(ret_port_enh_BSC);
r_mn_BSC   = log2simple(ret_port_mn_BSC);

r_std_DM   = log2simple(ret_port_std_DM);
r_weak_DM  = log2simple(ret_port_weak_DM);
r_enh_DM   = log2simple(ret_port_enh_DM);
r_mn_DM    = log2simple(ret_port_mn_DM);

r_std_BSC_DM  = log2simple(ret_port_std_DM_BSC);
r_weak_BSC_DM = log2simple(ret_port_weak_DM_BSC);
r_enh_BSC_DM  = log2simple(ret_port_enh_DM_BSC);
r_mn_BSC_DM   = log2simple(ret_port_mn_DM_BSC);

% Lista strategie
rets_all = {
    'STD',              r_std;
    'WEAKENED',         r_weak;
    'ENHANCED',         r_enh;
    'MN',               r_mn;
    'STD_BSC',          r_std_BSC;
    'WEAKENED_BSC',     r_weak_BSC;
    'ENHANCED_BSC',     r_enh_BSC;
    'MN_BSC',           r_mn_BSC;
    'STD_DM',           r_std_DM;
    'WEAKENED_DM',      r_weak_DM;
    'ENHANCED_DM',      r_enh_DM;
    'MN_DM',           r_mn_DM;
    'STD_DM_BSC',      r_std_BSC_DM;
    'WEAKENED_DM_BSC', r_weak_BSC_DM;
    'ENHANCED_DM_BSC', r_enh_BSC_DM;
    'MN_DM_BSC',       r_mn_BSC_DM
};

freq = 12;
names = {};
CAGR = []; Sharpe = []; Sortino = []; MaxDD = [];

for i = 1:size(rets_all,1)
    nm = rets_all{i,1};
    r  = rets_all{i,2};
    r  = r(isfinite(r));
    if numel(r) < 2, continue; end

    nav = cumprod(1 + r);
    n_years = numel(r) / freq;

    cagr    = nav(end)^(1/n_years) - 1;
    sharpe  = (mean(r,'omitnan')*freq) / (std(r,'omitnan')*sqrt(freq));
    dn      = r(r<0);
    sortino = (mean(r,'omitnan')*freq) / (std(dn,'omitnan')*sqrt(freq));
    peak    = cummax(nav);
    dd      = (nav - peak)./peak;
    maxdd   = -min(dd);

    names{end+1,1}   = nm;
    CAGR(end+1,1)    = cagr;
    Sharpe(end+1,1)  = sharpe;
    Sortino(end+1,1) = sortino;
    MaxDD(end+1,1)   = maxdd;
end

summaryPaper = table(CAGR, Sharpe, Sortino, MaxDD, 'RowNames', names);
disp(summaryPaper);



%% Metrica Omega

% Funzione metrica Omega
function M = metricsForOmega_full(r, CAGR_precomputed, MaxDD_precomputed)
    % Rimuove NaN e Inf
    r = r(:);
    r(~isfinite(r)) = [];
    if isempty(r)
        M = struct('SortinoMod', NaN, 'Calmar', NaN, 'Robust', NaN);
        return;
    end

    % NAV e drawdown 
    nav = [1; cumprod(1 + r)];
    cm = cummax(nav);
    dd = nav ./ cm - 1;
    MaxDD = -min(dd); % usato solo per Robust, non per Calmar

    % calcolo del calmar, uso il CAGR e il MaxDD già calcolati nella sezione performance
    Calmar = CAGR_precomputed / max(MaxDD_precomputed, eps);

    % sortino modificato
    rneg = r(r < 0);
    if isempty(rneg)
        SortinoMod = NaN;
    else
        avgNeg = mean(rneg, 'omitnan');
        stdNeg = std(rneg, 'omitnan');
        D = mean([abs(avgNeg), stdNeg], 'omitnan');
        mu = mean(r, 'omitnan');
        SortinoMod = mu / max(D, eps);
    end

    % robust index 
    thr = prctile(r, 99);
    r_trim = r(r <= thr);
    nav_trim = [1; cumprod(1 + r_trim)];
    CumRet_excl = nav_trim(end) - 1;

    inDD = nav < cummax(nav);
    runs = diff([0; inDD; 0]);
    sIdx = find(runs == 1); 
    eIdx = find(runs == -1) - 1;
    lengths = eIdx - sIdx + 1;
    if isempty(lengths)
        MaxUW = 0; AvgUW = 0;
    else
        MaxUW = max(lengths);
        AvgUW = mean(lengths);
    end

    denomUW = mean([MaxUW, AvgUW]);
    if denomUW == 0
        Robust = Inf;
    else
        Robust = CumRet_excl / denomUW;
    end

    % genero l'output
    M = struct('SortinoMod', SortinoMod, 'Calmar', Calmar, 'Robust', Robust);
end



% Definizione della lista di portafogli 
pairs = {
    'BENCH',           'equity_bench';
    'STD',              'equity_std';
    'WEAKENED',         'equity_weak';
    'ENHANCED',         'equity_enh';
    'MN',               'equity_mn';
    'STD_BSC',          'equity_std_BSC';
    'WEAKENED_BSC',     'equity_weak_BSC';
    'ENHANCED_BSC',     'equity_enh_BSC';
    'MN_BSC',           'equity_mn_BSC';
    'STD_DM',           'equity_std_DM';
    'WEAKENED_DM',      'equity_weak_DM';
    'ENHANCED_DM',      'equity_enh_DM';
    'MN_DM',            'equity_mn_DM';
    'STD_DM_BSC',       'equity_std_DM_BSC';
    'WEAKENED_DM_BSC',  'equity_weak_DM_BSC';
    'ENHANCED_DM_BSC',  'equity_enh_DM_BSC';
    'MN_DM_BSC',        'equity_mn_DM_BSC'
};



%% Calcolo delle metriche omega per tutti i portafogli

% Funzione eq2ret che converte in rendimenti semplici
function r = eq2ret(eq)
    eq = eq(:);                     
    r = diff(eq) ./ eq(1:end-1);    % calcolo rendimento semplice
end


disp(' ');
disp('calcolo metriche omega per tutti i portafogli');

rowNames = {};
SortinoMod = [];
Calmar     = [];
Robust     = [];

for i = 2:size(pairs,1)   % parte da 2, salta BENCH
    nm = pairs{i,1};
    vn = pairs{i,2};
    if ~exist(vn,'var'), continue; end
    eq = eval(vn); eq = eq(:);
    eq = eq(isfinite(eq));
    if numel(eq) < 2, continue; end

    % rendimenti mensili semplici
    r = eq2ret(eq);
    M = metricsForOmega_full(r, summaryPaper.CAGR(i-1), summaryPaper.MaxDD(i-1)); % i-1 perché summaryPaper ha 16 righe

    % salva i risultati in vettori
    rowNames{end+1,1}  = nm;
    SortinoMod(end+1,1) = M.SortinoMod;
    Calmar(end+1,1)     = M.Calmar;
    Robust(end+1,1)     = M.Robust;
end

% costruisci direttamente la tabella completa con i RowNames
summaryOmega = table(SortinoMod, Calmar, Robust, 'RowNames', rowNames);

disp(' ');
disp('Metriche omega di tutti i portafogli');
disp(summaryOmega);


%% calcolo metriche benchmark

% Rendimenti semplici del benchmark
ret_bench_s = eq2ret(equity_bench);

% Calcolo CAGR e MaxDD del BENCH (da usare nel Calmar)
freq = 12;
r = ret_bench_s(:);
r = r(isfinite(r));
nav = cumprod(1 + r);
ny  = numel(r)/freq;
CAGR_bench  = nav(end)^(1/ny) - 1;
peak = cummax(nav);
dd   = (nav - peak)./peak;
MaxDD_bench = -min(dd);

% Calcolo metriche Omega per il BENCH (con i parametri GIUSTI del BENCH)
M_bench = metricsForOmega_full(ret_bench_s, CAGR_bench, MaxDD_bench);

fprintf('SortinoMod (Benchmark) = %.4f\n', M_bench.SortinoMod);
fprintf('Calmar (Benchmark)     = %.4f\n', M_bench.Calmar);
fprintf('Robust (Benchmark)     = %.4f\n', M_bench.Robust);

% Inserisci/aggiorna BENCH nella tabella
summaryOmega{'BENCH', {'SortinoMod','Calmar','Robust'}} = [M_bench.SortinoMod, M_bench.Calmar, M_bench.Robust];


%% calcolo di omega come media equipesata delle differenze % con il benchmark

S_b = summaryOmega{'BENCH','SortinoMod'};
C_b = summaryOmega{'BENCH','Calmar'};
R_b = summaryOmega{'BENCH','Robust'};

OmegaFinal = nan(height(summaryOmega),1);
portNames  = summaryOmega.Properties.RowNames;

epsv = 1e-8;

for i = 1:height(summaryOmega)
    S_i = summaryOmega.SortinoMod(i);
    C_i = summaryOmega.Calmar(i);
    R_i = summaryOmega.Robust(i);

    if isfinite(S_i) && isfinite(S_b)
        relS = (S_i - S_b) / max(abs(S_b), epsv);
    else
        relS = NaN;
    end

    if isfinite(C_i) && isfinite(C_b)
        relC = (C_i - C_b) / max(abs(C_b), epsv);
    else
        relC = NaN;
    end

    if isfinite(R_i) && isfinite(R_b)
        relR = (R_i - R_b) / max(abs(R_b), epsv);
    else
        relR = NaN;
    end

    OmegaFinal(i) = mean([relS, relC, relR], 'omitnan');
end

summaryOmega.Omega = OmegaFinal;

disp(' ');
disp('tabella metrica omega');
disp(summaryOmega);



%% Metriche sulla volatilità (intero periodo, derivate dalle equity line)

% Funzione per metriche volatilità
function M = metricsVolatility(r)
    r = r(:);
    r = r(isfinite(r));  % rimuove NaN e Inf
    if isempty(r)
        M = struct('Vol', NaN, 'Skew', NaN, 'Q01', NaN);
        return;
    end

    % Deviazione standard annualizzata
    M.Vol  = std(r) * sqrt(12);

    % Skewness realizzata 
    M.Skew = skewness(r, 0);

    % 1% percentile 
    M.Q01  = quantile(r, 0.01);
end


% Lista dei portafogli (usando rendimenti derivati dalle equity line)
port_names_vol = {
    'STD',             eq2ret(equity_std);
    'WEAKENED',        eq2ret(equity_weak);
    'ENHANCED',        eq2ret(equity_enh);
    'MN',              eq2ret(equity_mn);
    'STD_BSC',         eq2ret(equity_std_BSC);
    'WEAKENED_BSC',    eq2ret(equity_weak_BSC);
    'ENHANCED_BSC',    eq2ret(equity_enh_BSC);
    'MN_BSC',          eq2ret(equity_mn_BSC);
    'STD_DM',          eq2ret(equity_std_DM);
    'WEAKENED_DM',     eq2ret(equity_weak_DM);
    'ENHANCED_DM',     eq2ret(equity_enh_DM);
    'MN_DM',           eq2ret(equity_mn_DM);
    'STD_DM_BSC',      eq2ret(equity_std_DM_BSC);
    'WEAKENED_DM_BSC', eq2ret(equity_weak_DM_BSC);
    'ENHANCED_DM_BSC', eq2ret(equity_enh_DM_BSC);
    'MN_DM_BSC',       eq2ret(equity_mn_DM_BSC);
};

% Calcolo metriche
names_vol  = port_names_vol(:,1);
Vol  = nan(numel(names_vol),1);
Skew = nan(numel(names_vol),1);
Q01  = nan(numel(names_vol),1);

for i = 1:numel(names_vol)
    r = port_names_vol{i,2};
    m = metricsVolatility(r);
    Vol(i)  = m.Vol;
    Skew(i) = m.Skew;
    Q01(i)  = m.Q01;
end

% Tabella 
summaryVolatility = table(Vol, Skew, Q01, 'RowNames', names_vol);

disp(' ');
disp('metriche di volatilità');
disp(summaryVolatility);

%% Riepilogo metriche performance e volatilità
disp(' ');
disp('RIEPILOGO COMPLETO (Metriche performance e volatilità)');

% Usa direttamente i risultati di summaryPaper (già corretti)
allNames = summaryPaper.Properties.RowNames;

% Crea tabella finale vuota con tutte le metriche
summaryAll = summaryPaper;  % copia diretta dei risultati corretti
summaryAll.Vol  = NaN(height(summaryAll),1);
summaryAll.Skew = NaN(height(summaryAll),1);
summaryAll.Q01  = NaN(height(summaryAll),1);

% Riempimento dei valori di volatilità (se disponibili)
for i = 1:numel(allNames)
    nm = allNames{i};
    if ismember(nm, summaryVolatility.Properties.RowNames)
        summaryAll.Vol(i)  = summaryVolatility.Vol(nm);
        summaryAll.Skew(i) = summaryVolatility.Skew(nm);
        summaryAll.Q01(i)  = summaryVolatility.Q01(nm);
    end
end

disp(summaryAll);


%% esportazione tabelle principali in formato csv

% Regressione Fama-French
writetable(addvars(summary, string(summary.Properties.RowNames), 'Before', 1, 'NewVariableNames', 'Strategy'),'FamaFrench_results.csv');

% Metriche Omega
writetable(addvars(summaryOmega, string(summaryOmega.Properties.RowNames), 'Before', 1, 'NewVariableNames', 'Strategy'),'Omega_metrics.csv');

% Metriche Performance e Volatilità
writetable(addvars(summaryAll, string(summaryAll.Properties.RowNames), 'Before', 1, 'NewVariableNames', 'Strategy'),'Performance_Volatility.csv');




