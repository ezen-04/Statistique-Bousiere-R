# Gestion des dépendances
pkgs <- c("quantmod", "xts", "tseries", "quantreg", "fitdistrplus", 
          "fGarch", "moments", "PerformanceAnalytics")
install.packages(pkgs)


library(quantmod)
library(xts)
library(tseries)
library(quantreg)
library(fitdistrplus)
library(fGarch)
library(moments)
library(PerformanceAnalytics)

# Setup des univers et tickers
actifs <- c("USA", "Europe", "Japon", "Chine", "Hong_Kong", 
            "Inde", "Bresil", "Afrique_du_Sud", "Australie", "Egypte")

tickers <- c(
  "USA" = "^GSPC", "Europe" = "^STOXX50E", "Japon" = "^N225", 
  "Chine" = "000001.SS", "Hong_Kong" = "^HSI", "Inde" = "^BSESN", 
  "Bresil" = "^BVSP", "Afrique_du_Sud" = "^J203.JO", "Australie" = "^AXJO", 
  "Egypte" = "EGPT"
)

ref_systeme <- "^GSPC" 
start_date  <- "2018-01-01"
end_date    <- "2026-06-10"

# Pull des donnees Yahoo Finance
cat("Recuperation des indices via Yahoo...\n")
getSymbols(c(tickers, ref_systeme), from = start_date, to = end_date, src = "yahoo", adjusted = TRUE)

# Alignement de la matrice des prix ajutes
list_p <- list()
for(n in names(tickers)) {
  list_p[[n]] <- Ad(get(sub("^\\^", "", tickers[n])))
}
mat_prix <- do.call(merge, list_p)
colnames(mat_prix) <- actifs

# Calcul des log-rendements bruts
r_multis_brut <- diff(log(mat_prix))
r_sys_brut    <- diff(log(Ad(get(sub("^\\^", "", ref_systeme)))))

# Structure d'accueil des stats finales
df_res <- data.frame(
  Actif = character(), Skewness = numeric(), Kurtosis = numeric(), JB_p = numeric(),
  LB_ret_p = numeric(), LB_sq_p = numeric(), Lev_corr = numeric(), AIC_norm = numeric(),
  VaR_hist = numeric(), CVaR_hist = numeric(), VaR_stud = numeric(), CoVaR = numeric(),
  stringsAsFactors = FALSE
)

# Configuration du seuil de risque (95%)
alpha <- 0.05

# Boucle principale par pays
for(i in actifs) {
  cat("Traitement :", i, "\n")
  
  # Nettoyage des NA locaux (fermetures et fetes specifiques)
  r_ts  <- na.omit(r_multis_brut[, i])
  r_vec <- as.numeric(r_ts)
  
  if(length(r_vec) < 100) next
  
  # 1. Stylized facts & tests de base
  sk   <- skewness(r_vec)
  kt   <- kurtosis(r_vec) - 3
  jb   <- jarque.bera.test(r_vec)$p.value
  lb   <- Box.test(r_vec, lag = 10, type = "Ljung-Box")$p.value
  lb_2 <- Box.test(r_vec^2, lag = 10, type = "Ljung-Box")$p.value
  
  n_obs <- length(r_vec)
  leverage <- cor(r_vec[1:(n_obs-1)], (r_vec[2:n_obs])^2)
  
  # 2. Fit de distribs
  fit_n <- fitdist(r_vec, "norm")
  aic_n <- fit_n$aic
  
  # 3. Calculs VaR & CVaR (Expected Shortfall) univaries
  v_h  <- -as.numeric(VaR(r_ts, p = 1 - alpha, method = "historical"))
  cv_h <- -as.numeric(ES(r_ts, p = 1 - alpha, method = "historical"))
  
  v_s <- NA
  tryCatch({
    fit_t <- sstdFit(r_vec)
    v_s   <- -qsstd(alpha, mean = fit_t$estimate[["mean"]], sd = fit_t$estimate[["sd"]], nu = fit_t$estimate[["nu"]])
  }, error = function(e) {})
  
  # 4. Estimation de la CoVaR via regression quantile (Adrian & Brunnermeier)
  pair <- merge(r_sys_brut, r_ts, all = FALSE)
  colnames(pair) <- c("Y", "X")
  pair <- as.data.frame(na.omit(pair))
  
  var_x <- -quantile(pair$X, probs = alpha)
  fit_q <- rq(Y ~ X, data = pair, tau = alpha)
  
  co_val <- -(coef(fit_q)[1] + coef(fit_q)[2] * (-var_x))
  
  # Compilation de la ligne
  df_res[i, ] <- c(i, sk, kt, jb, lb, lb_2, leverage, aic_n, v_h, cv_h, v_s, co_val)
}

# Formatage final du tableau
rownames(df_res) <- df_res$Actif
numeric_cols     <- 2:12
df_res[, numeric_cols] <- lapply(df_res[, numeric_cols], as.numeric)

cat("Tableau reacpitulatif :\n")
print(round(df_res[, numeric_cols], 5))
