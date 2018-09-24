# sqlmlutils

sqlmlutils is an R package to help execute R code on a SQL Server machine.

# Installation

Run 
```
R CMD INSTALL dist/sqlmlutils_0.5.0.zip
```
OR
To build a new package file and install, run
```
.\buildandinstall.cmd
```

# Getting started

Shown below are the important functions sqlmlutils provides:
```R
connectionInfo                      # Create a connection string for connecting to the SQL Server

executeFunctionInSQL                # Execute an R function inside the SQL database
executeScriptInSQL                  # Execute an R script inside the SQL database
executeSQLQuery                     # Execute a SQL query on the database and return the resultant table

createSprocFromFunction             # Create a stored procedure based on a R function inside the SQL database
createSprocFromScript               # Create a stored procedure based on a R script inside the SQL database
checkSproc                          # Check whether a stored procedure exists in the SQL database
dropSproc                           # Drop a stored procedure in the SQL database
executeSproc                        # Execute a stored procedure in the SQL database

sql_install.packages                # Install packages in the SQL database
sql_remove.packages                 # Remove packages from the SQL database
sql_installed.packages              # Enumerate packages that are installed on the SQL database
```

# Examples

### Execute In SQL
##### Execute an R function in database using sp_execute_external_script

```R
library(sqlmlutils)
connection <- connectionInfo()

funcWithArgs <- function(arg1, arg2){
    return(c(arg1, arg2))
}
result <- executeFunctionInSQL(connection, funcWithArgs, arg1="result1", arg2="result2")
```

##### Generate a linear model without the data leaving the machine

```R
library(sqlmlutils)
connection <-  connectionInfo(database="AirlineTestDB")

linearModel <- function(in_df, xCol, yCol) {
    lm(paste0(yCol, " ~ ", xCol), in_df)
}

model <- executeFunctionInSQL(connectionString = connection, func = linearModel, xCol = "CRSDepTime", yCol = "ArrDelay", 
                                inputDataQuery = "SELECT TOP 100 * FROM airline5000")
model
```

##### Execute a SQL Query from R

```R
library(sqlmlutils)
connection <-  connectionInfo(database="AirlineTestDB")

dataTable <- executeSQLQuery(connectionString = connection, sqlQuery="SELECT TOP 100 * FROM airline5000")
stopifnot(nrow(dataTable) == 100)
stopifnot(ncol(dataTable) == 30)
```

### Stored Procedures (Sproc)
##### Create and call a T-SQL stored procedure based on a R function

```R
library(sqlmlutils)

spPredict <- function(inputDataFrame) {
    library(RevoScaleR)
    model <- rxLinMod(ArrDelay ~ CRSDepTime, inputDataFrame)
    rxPredict(model, inputDataFrame)
}

connection <- connectionInfo(database="AirlineTestDB")
inputParams <- list(inputDataFrame = "Dataframe")

name = "prediction"

createSprocFromFunction(connectionString = connection, name = name, func = spPredict, inputParams = inputParams)
stopifnot(checkSproc(connectionString = connection, name = name))

predictions <- executeSproc(connectionString = connection, name = name, inputDataFrame = "select ArrDelay, CRSDepTime, DayOfWeek from airline5000")
stopifnot(nrow(predictions) == 5000)

dropSproc(connectionString = connection, name = name)
```

### Package Management 
##### Install and remove packages from SQL Server

```R
library(sqlmlutils)
connection <- connectionInfo(database="AirlineTestDB")

# install glue on sql server
pkgs <- c("glue")
sql_install.packages(connectionString = connection, pkgs, verbose = TRUE, scope="PUBLIC")

# confirm glue is installed on sql server
r<-sql_installed.packages(connectionString = connection, fields=c("Package", "LibPath", "Attributes", "Scope"))
View(r)

# use glue on sql server
useLibraryGlueInSql <- function()
{
    library(glue)

    name <- "Fred"
    age <- 50
    anniversary <- as.Date("1991-10-12")
    glue('My name is {name},',
         'my age next year is {age + 1},',
         'my anniversary is {format(anniversary, "%A, %B %d, %Y")}.')
}

result <- executeFunctionInSQL(connectionString = connection, func = useLibraryGlueInSql)
print(result)

# remove glue from sql server
sql_remove.packages(connectionString = connection, pkgs, scope="PUBLIC")
```

# Notes for Developers

### Running the tests

1. Make sure a SQL Server with an updated ML Services R is running on localhost. 
2. Restore the AirlineTestDB from the .bak file in this repo 
3. Make sure Trusted (Windows) authentication works for connecting to the database
    
### Notable TODOs and open issues

1. Output Parameter execution does not work - RODBCext limitations?
2. Testing from a Linux client has not been performed.
