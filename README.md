# pmd4tia
Proof of concept implementation for TIAs public PLSQL Database Best Practices using PMD
Use of this functionality requries you to have rights to use TIA - The Insurance Application. See www.tia.dk 

# Usage (to be improved)
## Checking your code with the rules
 1. Download the latest version of [PMD](https://pmd.github.io/)
 2. Clone this repo 
 3. Run PMD with the rules 
 - you can run it with the pmd2browser.cmd file or with PMD directly
 - Currently the Maven things does not work - help needed!
 
## Making new rules
 1. Read https://pmd.github.io/pmd-5.5.3/customizing/howtowritearule.html
 2. Find designer.bat in your local copy of PMD - which you downloaded :) 
 3. Find some ugly code to past in the upper left
 4. Write the XPath expression
 5. Fork this repo, and commit your changes as XML rules files
 6. Make a pull request
 

# Rules Overview
## Rules from PLSQL Standards from wiki7.tia.dk
URL: http://wiki7.tia.dk/index.php/PL/SQL_Standards
(note this is not public - sorry - for customers only)

See the [TIA Strict rules](/rulesets/plsql/tia_strict.xml) files
