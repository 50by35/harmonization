/* =====================================================================
CMR_2025_FDS_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Cameroon FDS (refugee welfare survey)
2025 to the 50by35 schema

Inputs : $REFUGEE_RAW_DATA/Cameroon/FDS_WR_Welfare_HH.dta
         $REFUGEE_RAW_DATA/Cameroon/FDS_WR_BasicInf.dta
         $REFUGEE_RAW_DATA/Cameroon/FDS_WR_Ind.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/CMR_2025_FDS_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Cameroon block), with welfare_self
added: the source's replicability script left assistance/aid unused for
this survey, but the welfare file directly provides a nominal
consumption-net-of-aid variable (nom_cons_minus_aid) that this script
applies through the same spatial/temporal deflation used for welfare.
Sample: pops==1 ("Refugie/Demandeur d'asile"). Hosts (pops==2) dropped.
CAUTION: pops==1 is a single combined code for refugees AND
asylum-seekers — none of the raw files (welfare, basic infrastructure,
individual) carry a variable that separates the two. Per the 50by35
monitoring population (refugees only, no asylum-seekers/IDPs), this
survey cannot currently be restricted further; flag to the methodology
team before treating this file's totals as refugee-only.
Welfare is CONSUMPTION (nom_cons, spatially/temporally deflated, per
capita), consistent with the source's own poverty methodology.
welfare_type = 1.
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

* ---- household level ----------------------------------------------------
use `"`rawroot'/Cameroon/FDS_WR_Welfare_HH.dta"', clear

* refugees only
keep if pops==1

* welfare: nominal consumption, spatially/temporally deflated,
* per capita, in LCU (XAF). welfare_type = 1 (consumption).
gen double welfare = (nom_cons/(def_spa*def_temp))/hhsize

* welfare_self: consumption net of aid, provided directly by the source
* (nom_cons_minus_aid), same deflation and per-capita basis as welfare.
gen double welfare_self = max(nom_cons_minus_aid/(def_spa*def_temp), 0)/hhsize

* households without a positive consumption aggregate or a positive
* sampling weight cannot conform to the schema
qui count if missing(welfare) | welfare<=0 | missing(hhweight) | hhweight<=0
di as txt "Dropping " r(N) " observations with missing/zero consumption aggregate or weight"
drop if missing(welfare) | welfare<=0 | missing(hhweight) | hhweight<=0

* ---- merge household infrastructure + individuals -------------------------
merge 1:1 hhid using `"`rawroot'/Cameroon/FDS_WR_BasicInf.dta"', ///
    keep(3) nogen keepusing(elec_ac)
merge 1:m hhid using `"`rawroot'/Cameroon/FDS_WR_Ind.dta"', ///
    keep(3) nogen keepusing(s01q04 s02q03 s02q11a emp01 emp02 emp03 emp04 emp05 Neduc_scol)

* ---- schema variables ----------------------------------------------------
gen str3 code = "CMR"
gen int  year        = 2025
gen      survname    = "FDS"

tostring hhid, replace
bysort hhid: gen pidn = _n
tostring pidn, gen(pid)
drop pidn

gen byte   welfare_type = 1
gen double weight       = hhweight    // HH weight applied to each member

* urban/camp: source rur_urb is inverted (0=Urban/1=Rural per reference
* replicability package's recode); camp is a separate refugee-only flag.
gen byte urban = (rur_urb==0)
* camp already 0/1 in source, missing for hosts (not applicable here
* since hosts are already dropped)

* optional variables
gen int    hhsize2 = hhsize
drop hhsize
rename hhsize2 hhsize
gen double age = s01q04
replace    age = . if !inrange(age, 0, 120)   // sentinel codes (e.g. -3)

gen byte educat4 = Neduc_scol         // source already 1 None … 4 Secondary-2nd-cycle+
* note: source lumps secondary 2nd cycle and tertiary into category 4 —
* the schema's tertiary category is therefore likely overstated here;
* confirm with the methodology team if a finer breakdown becomes available

gen byte empstat = 0 if age >= 5
replace  empstat = 1 if age >= 5 & (emp01==1 | emp02==1 | emp03==1 | emp04==1 | emp05==1)
replace  empstat = 4 if missing(empstat) & age < 15
recode   empstat (0=3)                // not reporting any work activity -> outside LF

* ---- labels per the 50by35 schema ----------------------------------------
label drop _all
label define welfare_type 1 "Consumption" 2 "Income" 3 "Expenditure"
label define urban   0 "Rural" 1 "Urban"
label define camp    0 "Non-camp" 1 "Camp"
label define educat4 1 "No education" 2 "Primary" 3 "Secondary" 4 "Tertiary"
label define empstat 1 "Employed" 2 "Unemployed" 3 "Out of labor force" 4 "Not applicable"
foreach v in welfare_type urban camp educat4 empstat {
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
label variable educat4      "Highest education (4 cat.)"
label variable empstat      "Employment status"

keep  code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age educat4 empstat
order code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age educat4 empstat

isid hhid pid
compress
save "`outdir'/CMR_2025_FDS_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/CMR_2025_FDS_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
