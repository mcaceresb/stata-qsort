*! version 0.1.0 28Jul2017 Mauricio Caceres Bravo, mauricio.caceres.bravo@gmail.com
*! implementation of -sort- and -gsort- using C-plugins

capture program drop qsort
program define qsort
    version 13

    * Time the entire function execution
    {
        cap timer off 99
        cap timer clear 99
        timer on 99
    }

    syntax anything, [*]
    cap matrix drop __qsort_invert
    local parse    `anything'
    local varlist  ""
    local skip   = 0
    local invert = 0
    while ( trim("`parse'") != "" ) {
        gettoken var parse: parse, p(" -+")
        if inlist("`var'", "-", "+") {
            matrix __qsort_invert = nullmat(__qsort_invert), ( "`var'" == "-" )
            local skip   = 1
            local invert = ( "`var'" == "-" )
        }
        else {
            cap confirm variable `var'
            if ( _rc ) {
                di as err "Variable '`var'' does not exist. Syntax:"
                di as err "qsort [+|-]varname [[+|-]varname ...], [options]"
                exit _rc
            }
            if ( `skip' ) {
                local skip = 0
            }
            else {
                matrix __qsort_invert = nullmat(__qsort_invert), 0
            }
            local varlist `varlist' `var'
        }
    }

    local 0 `varlist', `options'
    syntax varlist(min = 1), [Verbose Benchmark qsort stable]

    * Andrew Mauer's trick? From ftools
    * ---------------------------------

	loc sortvar : sortedby
	if ( "`sortvar'" == "`varlist'" ) {
        if ( "`verbose'" != "" ) di as txt "(already sorted)"
		exit 0
	}
	else if ( "`sortvar'" != "" ) {
		* Andrew Maurer's trick to clear `: sortedby'
		loc sortvar : word 1 of `sortvar'
		loc val = `sortvar'[1]
		cap replace `sortvar' = 0         in 1
		cap replace `sortvar' = .         in 1
		cap replace `sortvar' = ""        in 1
		cap replace `sortvar' = "."       in 1
		cap replace `sortvar' = `val'     in 1
		cap replace `sortvar' = `"`val'"' in 1
		assert "`: sortedby'" == ""
	}

    * Verbose and benchmark printing
    * ------------------------------

    if ( "`verbose'" == "" ) {
        local verbose = 0
    }
    else {
        local verbose = 1
    }

    if ( "`benchmark'" == "" ) {
        local benchmark = 0
    }
    else {
        local benchmark = 1
    }

    scalar __qsort_qsort     = ( "`qsort'" == "qsort" )
    scalar __qsort_verbose   = `verbose'
    scalar __qsort_benchmark = `benchmark'

    if ( `verbose'  | `benchmark' ) local noi noisily

    * Parse sort variables
    * --------------------

    if ( "`stable'" == "stable" ) {
        tempvar ix
        if ( `=_N < 2^31' ) {
            gen long `ix' = _n
        }
        else {
            gen `c(type)' `ix' = _n
        }
    }

    qui ds *
    local memvars `r(varlist)'

    qui ds `varlist' `ix'
    local sortvars `r(varlist)'

    scalar __qsort_kvars_sort = `:list sizeof sortvars'
    parse_sort_types `sortvars'

    * If benchmark, output program setup time
    {
        cap timer off 99
        qui timer list
        if ( `benchmark' ) di "Program set up executed in `:di trim("`:di %21.4gc r(t99)'")' seconds"
        cap timer clear 99
        timer on 99
    }

    * Run the plugin
    * --------------

    cap noi qsort_inner `sortvars', benchmark(`benchmark')
    if ( _rc ) exit _rc

    * If benchmark, output program setup time
    {
        cap timer off 99
        qui timer list
        if ( `benchmark' ) di "Stata shuffle executed in `:di trim("`:di %21.4gc r(t99)'")' seconds"
        cap timer clear 99
        timer on 99
    }

    * Fianl sort (if benchmark, output program setup time)
    if ( !`invert' ) {
        sort `varlist'
        cap timer off 99
        qui timer list
        if ( `benchmark' ) di "Final sort executed in `:di trim("`:di %21.4gc r(t99)'")' seconds"
        cap timer clear 99
        timer on 99
    }
    else {
        cap timer off 99
        qui timer list
        cap timer clear 99
    }

    * Clean up after yourself
    * -----------------------

    cap matrix drop __qsort_strpos
    cap matrix drop __qsort_numpos

    cap matrix drop __qsort_sortvars
    cap matrix drop __qsort_sortmin
    cap matrix drop __qsort_sortmax

    cap matrix drop c_qsort_sortmiss
    cap matrix drop c_qsort_sortmin
    cap matrix drop c_qsort_sortmax

    cap scalar drop __qsort_is_int
end

capture program drop qsort_inner
program qsort_inner, sortpreserve
    syntax varlist, benchmark(int)
    cap noi plugin call qsort_plugin `varlist' `_sortindex', sort
    if ( _rc ) exit _rc
    mata: st_store(., "`_sortindex'", invorder(st_data(., "`_sortindex'")))
    * If benchmark, output program setup time
    {
        cap timer off 99
        qui timer list
        if ( `benchmark' ) di "Plugin executed in `:di trim("`:di %21.4gc r(t99)'")' seconds"
        cap timer clear 99
        timer on 99
    }
    exit 0
end

cap program drop qsort_plugin
program qsort_plugin, plugin using(`"qsort_`:di lower("`c(os)'")'.plugin"')

* Parse sort variable types; encode as numbers
* --------------------------------------------

capture program drop parse_sort_types
program parse_sort_types
    syntax varlist(min = 1)

    cap matrix drop __qsort_strpos
    cap matrix drop __qsort_numpos

    cap matrix drop __qsort_sortvars
    cap matrix drop __qsort_sortmin
    cap matrix drop __qsort_sortmax

    cap matrix drop c_qsort_sortmiss
    cap matrix drop c_qsort_sortmin
    cap matrix drop c_qsort_sortmax

    * If any strings, skip integer check
    * ----------------------------------

    local kmaybe  = 1
    foreach sortvar of varlist `varlist' {
        if regexm("`:type `sortvar''", "str") local kmaybe = 0
    }

    * Check whether we only have integers
    * -----------------------------------

    local varnum  ""
    local knum    = 0
    local khash   = 0
    local intlist ""
    foreach sortvar of varlist `varlist' {
        if ( `kmaybe' ) {
            if inlist("`:type `sortvar''", "byte", "int", "long") {
                local ++knum
                local varnum `varnum' `sortvar'
                local intlist `intlist' 1
            }
            else if inlist("`:type `sortvar''", "float", "double") {
                if ( `=_N > 0' ) {
                    cap plugin call qsort_plugin `sortvar', isint
                    if ( _rc ) exit _rc
                }
                else scalar __qsort_is_int = 0
                if ( `=scalar(__qsort_is_int)' ) {
                    local ++knum
                    local varnum `varnum' `sortvar'
                    local intlist `intlist' 1
                }
                else {
                    local kmaybe = 0
                    local ++khash
                    local intlist `intlist' 0
                }
            }
            else {
                local kmaybe = 0
                local ++khash
                local intlist `intlist' 0
            }
        }
        else {
            local ++khash
            local intlist `intlist' 0
        }
    }
    else {
        foreach sortvar of varlist `varlist' {
            local intlist `intlist' 0
        }
    }

    * Set up max-min for integer sort in C
    * ------------------------------------

    * If so, set up min and max in C. Later we will check whether we can use a
    * bijection of the sort variables to the whole numbers as our index
    if ( (`knum' > 0) & (`khash' == 0) ) {
        matrix c_qsort_sortmiss = J(1, `knum', 0)
        matrix c_qsort_sortmin  = J(1, `knum', 0)
        matrix c_qsort_sortmax  = J(1, `knum', 0)
        if ( `=_N > 0' ) {
            cap plugin call qsort_plugin `varnum', setup
            if ( _rc ) exit _rc
        }
        matrix __qsort_sortmin = c_qsort_sortmin
        matrix __qsort_sortmax = c_qsort_sortmax + c_qsort_sortmiss
    }

    * Encode type of each variable
    * ----------------------------

    * See 'help data_types'; we encode string types as their length,
    * integer types as -1, and other numeric types as 0. Each are
    * handled differently when sorting:
    *     - All integer types: Try to map them to the natural numbers
    *     - All same type: Invoke loop that reads the same type
    *     - A mix of types: Invoke loop that reads a mix of types
    *
    * The loop that reads a mix of types switches from reading strings
    * to reading numeric variables in the order the user specified the
    * sort variables, which is necessary for the sort to be consistent.
    * But this version of the loop is marginally slower than the version
    * that reads the same type throughout.
    *
    * Last, we need to know the length of the data to read them into
    * C and sort them. Numeric data are 8 bytes (we will read them
    * as double) and strings are read into a string buffer, which is
    * allocated the length of the longest sort string variable.

    local sort_post  0
    local sort_types ""
    foreach sortvar of varlist `varlist' {
        local ++sort_post
        gettoken is_int intlist: intlist
        local stype: type `sortvar'
        if ( (`is_int' | inlist("`stype'", "byte", "int", "long")) ) {
            local sort_types `sort_types' num
            matrix __qsort_sortvars = nullmat(__qsort_sortvars), -1
            matrix __qsort_numpos   = nullmat(__qsort_numpos), `sort_post'
        }
        else {
            matrix __qsort_sortmin = J(1, `:list sizeof varlist', 0)
            matrix __qsort_sortmax = J(1, `:list sizeof varlist', 0)
            if regexm("`stype'", "str([1-9][0-9]*|L)") {
                local sort_types `sort_types' str
                if ( regexs(1) == "L" ) {
                    tempvar strlen
                    gen `strlen' = length(`sortvar')
                    qui sum `strlen'
                    matrix __qsort_sortvars = nullmat(__qsort_sortvars), `r(max)'
                    matrix __qsort_strpos   = nullmat(__qsort_strpos),   `sort_post'
                }
                else {
                    matrix __qsort_sortvars = nullmat(__qsort_sortvars), `=regexs(1)'
                    matrix __qsort_strpos   = nullmat(__qsort_strpos),   `sort_post'
                }
            }
            else {
                local sort_types `sort_types' num
                if inlist("`stype'", "float", "double") {
                    matrix __qsort_sortvars = nullmat(__qsort_sortvars), 0
                    matrix __qsort_numpos   = nullmat(__qsort_numpos), `sort_post'
                }
                else if ( inlist("`stype'", "byte", "int", "long") ) {
                    matrix __qsort_sortvars = nullmat(__qsort_sortvars), 0
                    matrix __qsort_numpos   = nullmat(__qsort_numpos), `sort_post'
                }
                else {
                    di as err "variable `byvar' has unknown type '`stype''"
                }
            }
        }
    }
end
