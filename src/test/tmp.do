version 13
clear all
set more off
set varabbrev off
* set seed 42
set seed 1729
set linesize 128

* sysuse auto,  clear
* set rmsg on
* clear
* * set obs 1000000
* set obs 100000
* gen x = floor(rnormal())
* gen y = rnormal()
* qui ralpha rstr, l(5)
* qui ralpha rst2, l(3)
* replace rstr = rstr + "s"
* replace rst2 = rst2 + "someting longer"
* gen double id2 = _n
* gen byte dummy = 0
* gen idx = _n
* save /tmp/qsort, replace

set rmsg on
use /tmp/qsort, clear
sort rstr x rst2 y
cap drop st_idx
gen st_idx = _n
sort idx
qsort rstr x rst2 y, v b
assert st_idx == _n
