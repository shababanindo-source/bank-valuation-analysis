import excel "For Stata.xlsx", sheet("Sheet1") firstrow
********************************************************************************
* Research: Interaction Between Profitability, Risk, and Market Value
* Dependent Variable: Net Asset Value (NAV)
********************************************************************************
rename BankName                    bank
rename Year                        year
rename CapitalAdequacyRatio        car
rename AdvanceDepositratio         adr
rename NPLRate                     npl
rename NetAssetValueNAV            nav
rename NetProfitAfterTaxAnnualized netprofit
rename EPS12Month                  eps
rename ROEAnnualized               roe
rename ROAAnnualized               roa
capture ssc install winsor2
winsor2 roe npl nav, cuts(1 99) replace
sum roe
gen roe_c = roe - r(mean)
sum npl
gen npl_c = npl - r(mean)
gen int_c = roe_c * npl_c
summ roe npl car nav roa
pwcorr roe npl car nav roa, sig
reg nav roe_c npl_c car, robust
reg nav roe_c npl_c int_c car, robust
estat vif
reg nav c.roe##c.npl car, robust
sum npl, detail
local p25 = r(p25)
local p50 = r(p50)
local p75 = r(p75)
margins, dydx(roe) at(npl=(`p25' `p50' `p75'))
marginsplot, title("Marginal Effect of ROE on NAV at Different NPL Levels") ///
    ytitle("Marginal Effect of ROE on NAV") xtitle("NPL Levels") name(marg_nav, replace)
sum npl
gen high_npl = npl > r(mean)
twoway (lfit nav roe if high_npl==1, lcolor(red)) ///
       (lfit nav roe if high_npl==0, lcolor(blue)) ///
       (scatter nav roe if high_npl==1, mcolor(red%35)) ///
       (scatter nav roe if high_npl==0, mcolor(blue%35)), ///
       legend(order(1 "High NPL fit" 2 "Low NPL fit" 3 "High NPL" 4 "Low NPL")) ///
       title("ROE–NAV Relationship by NPL Level") ///
       ytitle("Net Asset Value (NAV)") xtitle("Return on Equity (ROE)") name(intplot_nav, replace)
graph export "ROE_NAV_Interaction.png", width(1400) replace
encode bank, gen(bank_id)
capture noisily xtset bank_id year
if _rc==0 {
    xtreg nav roe_c npl_c int_c car, fe vce(robust)
    xtreg nav roe_c npl_c int_c car, re vce(robust)
}
capture ssc install outreg2
outreg2 using "NAV_Results.doc", replace dec(3) ctitle("Baseline OLS (robust)") ///
    addtext(Dependent, NAV) keep(roe_c npl_c car)
outreg2 using "NAV_Results.doc", append dec(3) ctitle("Interaction OLS (robust)") ///
    addtext(Dependent, NAV) keep(roe_c npl_c int_c car)
outreg2 using "NAV_Results.doc", append dec(3) ctitle("Factor Syntax OLS (robust)") ///
    addtext(Dependent, NAV) keep(roe npl c.roe#c.npl car)
display "=== ANALYSIS COMPLETE ==="
display "Results exported to NAV_Results.doc and ROE_NAV_Interaction.png"
********************************************************************************
`
********************************************************************************
* Year-wise NAV Models (2020–2025)
* Assumes you already renamed: bank year nav roe npl car
********************************************************************************
* (Optional) Panel declaration (helps with checks; not required for yearwise OLS)
capture encode bank, gen(bank_id)
capture xtset bank_id year
* --- A) Create year-centered variables for interaction (per-year means) ---
bys year: egen roe_mean_y = mean(roe)
bys year: egen npl_mean_y = mean(npl)
gen roe_c_y = roe - roe_mean_y
gen npl_c_y = npl - npl_mean_y
gen int_c_y = roe_c_y * npl_c_y
* --- B) Run year-wise baseline OLS (NAV on ROE, NPL, CAR) ---
levelsof year, local(years)
display "================ YEAR-WISE BASELINE (robust) ================"
foreach y of local years {
    display "----- Year: `y' -----"
    reg nav roe npl car if year == `y', robust
}
* --- C) Run year-wise INTERACTION OLS (NAV on ROE_c, NPL_c, ROE×NPL, CAR) ---
display "================ YEAR-WISE INTERACTION (robust) ================"
foreach y of local years {
    display "----- Year: `y' -----"
    reg nav roe_c_y npl_c_y int_c_y car if year == `y', robust
}
* --- D) Export neatly to Word using esttab (install once if needed) ---
capture ssc install estout
* Baseline export
eststo clear
foreach y of local years {
    quietly eststo base_`y': reg nav roe npl car if year == `y', robust
}
esttab base_* using "Yearwise_NAV_Baseline.doc", replace ///
    title("Year-wise NAV Regressions: Baseline (robust)") ///
    se b(3) se(3) r2 ar2 nostar
* Interaction export
eststo clear
foreach y of local years {
    quietly eststo int_`y': reg nav roe_c_y npl_c_y int_c_y car if year == `y', robust
}
esttab int_* using "Yearwise_NAV_Interaction.doc", replace ///
    title("Year-wise NAV Regressions: Interaction (robust)") ///
    se b(3) se(3) r2 ar2 nostar
* --- E) Optional: also save as CSV-friendly tables via outreg2 ---
capture ssc install outreg2
* Baseline to one DOC
outreg2 using "Yearwise_NAV_Baseline_Summary.doc", replace dec(3) ctitle("Baseline: NAV = ROE + NPL + CAR")
foreach y of local years {
    outreg2 using "Yearwise_NAV_Baseline_Summary.doc", append dec(3) ///
        ctitle("Year `y'") addstat(Year, `y') ///
        keep(roe npl car) ///
        reg(nav roe npl car) if year==`y', robust
}
* Interaction to one DOC
outreg2 using "Yearwise_NAV_Interaction_Summary.doc", replace dec(3) ctitle("Interaction: NAV = ROE_c + NPL_c + ROE×NPL + CAR")
foreach y of local years {
    outreg2 using "Yearwise_NAV_Interaction_Summary.doc", append dec(3) ///
        ctitle("Year `y'") addstat(Year, `y') ///
        keep(roe_c_y npl_c_y int_c_y car) ///
        reg(nav roe_c_y npl_c_y int_c_y car) if year==`y', robust
}
display "=== DONE: Created Yearwise_NAV_Baseline.doc, Yearwise_NAV_Interaction.doc, and summary docs ==="
save "stata files (NAV) modified.dta"
putexcel set "Results.xlsx", modify
log using "Results.smcl"
