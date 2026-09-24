/* =====================================================================
CHL_2022_CASEN_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Chile CASEN 2022 to the 50by35 schema

Inputs : $REFUGEE_RAW_DATA/Chile/Base de datos Casen 2022 STATA_18 marzo 2024.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/CHL_2022_CASEN_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Chile block), with welfare_self
added: the source computed a net-of-aid income (ymoncorh = ytotcorh -
yaimcorh) but never carried it through the per-adult-equivalent/
temporal-deflation transformation applied to welfare — this script does.
Sample: refugees only — Venezuelan, Colombian, or Haitian mother's
country of residence (r1b_pais_esp_cod), the population groups the
source treats as forced displacement from these origin countries.
Interviews span Nov 2022-Feb 2023; a month-specific CPI/temporal
deflator (from the source package) puts income on a Dec-2022 basis.
Welfare is INCOME (income per adult equivalent, deflated, annualized).
welfare_type = 2.
===================================================================== */

version 18
clear
set more off

* ---- raw data source ------------------------------------------------------
* Reads from REFUGEE_RAW_DATA. The same files can also be fetched from
* datalibweb's FDPRAW collection instead (see chapters/04-access.qmd,
* requires the datalibweb Stata package + a registered token) — swap the
* `use`/`merge...using` lines below for a datalibweb call if needed.
local rawroot : env REFUGEE_RAW_DATA
if `"`rawroot'"' == "" {
    di as error "Set REFUGEE_RAW_DATA to the raw-data root folder"
    exit 601
}
local outdir : env FIFTYBY35_PROCESSED
if `"`outdir'"' == "" local outdir "~/Github/50by35-data/data/processed"

use `"`rawroot'/Chile/Base de datos Casen 2022 STATA_18 marzo 2024.dta"', clear

* refugees only: Venezuelan (513), Colombian (505), or Haitian (413)
* mother's country of residence
keep if inlist(r1b_pais_esp_cod, 513, 505, 413)

* ---- month-specific temporal deflator (interviews span Nov22-Feb23) -------
gen date_day    = dofc(fecha_entrev)
gen month_only  = month(date_day)
gen double def_temp = 1                    if month_only==11
replace     def_temp = 1.00287602          if month_only==12
replace     def_temp = 1.01088223863194    if month_only==1
replace     def_temp = 1.01026039642441    if month_only==2

* welfare: income per adult equivalent (yae), temporally deflated to
* Dec-2022 prices, annualized to LCU (CLP). welfare_type = 2 (income).
gen double welfare = (yae*12)/def_temp

* welfare_self: household income net of assistance/subsidies
* (ytotcorh - yaimcorh, HH monthly total), converted to the same
* per-adult-equivalent, deflated, annualized basis as welfare.
gen double welfare_self = (max(ytotcorh - yaimcorh, 0)/nae*12)/def_temp
replace    welfare_self = welfare if welfare_self > welfare & !missing(welfare)

* households without an income aggregate cannot conform to the schema
qui count if missing(welfare) | welfare<=0
di as txt "Dropping " r(N) " observations with missing or zero income"
drop if missing(welfare) | welfare<=0

* ---- schema variables ----------------------------------------------------
gen str3 code = "CHL"
gen int  year        = 2022
gen      survname    = "CASEN"

tostring folio, gen(hhid)
tostring id_persona, gen(pid)

gen byte   welfare_type = 2           // income
gen double weight       = expr        // HH weight applied to each member

gen byte camp = .                     // not applicable — no camp population in Chile

* optional variables
gen int    hhsize = numper
gen double age    = edad
replace    age    = . if !inrange(age, 0, 120)
gen byte   male   = (sexo==1)         // source: 1 Hombre / 2 Mujer

* educ: 0/1 None, 2/3/4 Primary, 5/6/7 Secondary, 8-12 Tertiary,
* -88 Don't know -> missing
recode educ (0/1=1) (2/4=2) (5/7=3) (8/12=4) (-88=.), gen(educat4)

gen byte empstat = 1 if activ==1
replace  empstat = 2 if activ==2
replace  empstat = 3 if activ==3
replace  empstat = 4 if missing(empstat) & age < 15

gen byte urban = (area==1)     // source: 1 Urbano / 2 Rural

* ---- labels per the 50by35 schema ----------------------------------------
label drop _all
label define welfare_type 1 "Consumption" 2 "Income" 3 "Expenditure"
label define male    0 "Female" 1 "Male"
label define urban   0 "Rural" 1 "Urban"
label define camp    0 "Non-camp" 1 "Camp"
label define educat4 1 "No education" 2 "Primary" 3 "Secondary" 4 "Tertiary"
label define empstat 1 "Employed" 2 "Unemployed" 3 "Out of labor force" 4 "Not applicable"
foreach v in welfare_type male urban camp educat4 empstat {
    label values `v' `v'
}

label variable code  "Country code"
label variable year         "Survey year"
label variable survname     "Survey name"
label variable hhid         "Household identifier"
label variable pid          "Person identifier"
label variable welfare      "Welfare aggregate (LCU, annual per capita)"
label variable welfare_type "Welfare measure type"
label variable welfare_self "Self-reliance-adjusted welfare (LCU, annual per capita)"
label variable weight       "Sampling weight"
label variable camp         "Camp/non-camp"
label variable urban        "Urban/rural"
label variable hhsize       "Household size"
label variable age          "Age"
label variable male         "Sex"
label variable educat4      "Highest education (4 cat.)"
label variable empstat      "Employment status"

keep  code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age male educat4 empstat
order code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age male educat4 empstat

isid hhid pid
compress
save "`outdir'/CHL_2022_CASEN_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/CHL_2022_CASEN_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
