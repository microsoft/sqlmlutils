# Copyright(c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license.


# the list with type conversion info
sqlTypes <- list(posixct = "datetime", numeric = "float",
                 character = "nvarchar(max)", integer = "int",
                 logical = "bit", raw = "varbinary(max)", dataframe = "nvarchar(max)")

getSqlType <- function(rType) {
    sqlTypes[[tolower(rType)]]
}

# creates the top part of the sql script (up to R code)
getHeader <- function(spName, inputParams, outputParams) {
    header <- c(paste0 ("CREATE PROCEDURE ", spName),
                handleHeadParams(inputParams, outputParams),
                "AS",
                "BEGIN TRY",
                "exec sp_execute_external_script",
                "@language = N'R',","@script = N'")
    return(paste0(header, collapse = "\n"))
}

handleHeadParams <- function(inputParams, outputParams)
{
    paramString <- c()

    makeString <- function(name, d, output = "") {
        rType <- d[[name]]
        sqlType <- getSqlType(rType)
        paste0("  @", name, "_outer ", sqlType, output)
    }

    for(name in names(inputParams)) {
        paramString <- c(paramString, makeString(name, inputParams))
    }
    for(name in names(outputParams)) {
        rType <- outputParams[[name]]
        if (tolower(rType) != "dataframe") {
            paramString <- c(paramString, makeString(name, outputParams, " output"))
        }
    }
    return(paste0(paramString, collapse = ",\n"))
}

generateTSQL <- function(func, spName, inputParams = NULL, outputParams = NULL ) {
    # header to drop and create a stored procedure
    header <- getHeader(spName, inputParams, outputParams)

    # vector containing R code
    rCode <- getRCode(func, outputParams)

    # tail of the sp
    tail <- getTail(inputParams, outputParams)

    register = paste0(header, rCode, tail, sep = "\n")
}

generateTSQLFromScript <- function(script, spName, inputParams, outputParams) {
    # header to drop and create a stored procedure
    header <- getHeader(spName, inputParams = inputParams, outputParams = outputParams)

    # vector containing R code
    rCode <- getRCodeFromScript(script = script, outputParams = outputParams)

    # tail of the sp
    tail <- getTail(inputParams = inputParams, outputParams = outputParams)

    paste0(header, rCode, tail, sep = "\n")
}



# creates the bottom part of the sql script (after R code)
getTail <- function(inputParams, outputParams) {
    tail <- c("'")
    tailParams <- handleTailParams(inputParams, outputParams)
    if (tailParams != "")
        tail <- c("',")
    tail <- c(tail,
              tailParams,
              "END TRY",
              "BEGIN CATCH",
              "THROW;",
              "END CATCH;")
    return(paste0(tail, collapse = "\n"))
}

handleTailParams <- function(inputParams, outputParams) {
    inDataString <- c()
    outDataString <- c()
    paramString <- c()
    overallParams <- c()

    makeString <- function(name, d, output = "") {
        rType <- d[[name]]
        if (tolower(rType) == "dataframe") {
            if (output=="") {
                c(paste0("@input_data_1 = @", name, "_outer"),
                  paste0("@input_data_1_name = N'", name, "'"))
            } else {
                c(paste0("@output_data_1_name = N'", name, "'"))
            }
        } else {
            sqlType <- getSqlType(rType)
            overallParams <<- c(overallParams, paste0("@", name, " ", sqlType, output))
            paste0("@", name, " = ", "@", name, "_outer", output)
        }
    }

    for(name in names(inputParams)) {
        rType <- inputParams[[name]]
        if (tolower(rType) == "dataframe") {
            inDataString <- c(makeString(name, inputParams))
        } else {
            paramString <- c(paramString, makeString(name, inputParams))
        }
    }
    for(name in names(outputParams)) {
        rType <- outputParams[[name]]
        if (tolower(rType) == "dataframe") {
            outDataString <- c(makeString(name, outputParams, " output"))
        } else {
            paramString <- c(paramString, makeString(name, outputParams, " output"))
        }
    }
    if (length(overallParams) > 0) {
        overallParams <- paste0(overallParams, collapse = ", ")
        overallParams <- paste0("@params = N'" , overallParams,"'")
    }
    return(paste0(c(inDataString, outDataString, overallParams, paramString), collapse = ",\n"))
}

getRCodeFromScript <- function(script, inputParams, outputParams) {
    # escape single quotes and get rid of tabs
    script <- sapply(script, gsub, pattern = "\t", replacement = "  ")
    script <- sapply(script, gsub, pattern = "'", replacement = "''")

    return(paste0(script, collapse = "\n"))
}

getRCode <- function(func, outputParams) {
    name <- as.character(substitute(func))

    funcBody <- deparse(func)

    # add on the function definititon
    funcBody[1] <- paste(name, "<-", funcBody[1], sep = " ")

    # escape single quotes and get rid of tabs
    funcBody <- sapply(funcBody, gsub, pattern = "\t", replacement = "  ")
    funcBody <- sapply(funcBody, gsub, pattern = "'", replacement = "''")

    inputParameters <- methods::formalArgs(func)

    funcInputNames <- paste(inputParameters, inputParameters,
                            sep = " = ")
    funcInputNames <- paste(funcInputNames, collapse = ", ")

    # add function call
    funcBody <- c(funcBody, paste0("result <- ", name,
                                   paste0("(", funcInputNames, ")")))

    # add appropriate ending
    ending <- getEnding(outputParams)
    funcBody <- c(funcBody, ending)
    return(paste0(funcBody, collapse = "\n"))
}

#
# Get ending string
# We change the result into an OutputDataSet - we only expect a single OutputDataSet result
getEnding <- function(outputParams) {
    outputDataSetName <- "OutputDataSet"
    for(name in names(outputParams)) {
        if (tolower(outputParams[[name]]) == "dataframe") {
            outputDataSetName <- name
        }
    }
    ending <- c( "if (is.data.frame(result)) {",
                 paste0("  ", outputDataSetName," <- result")
    )

    if (length(outputParams) > 0) {
        ending <- c(ending, "} else if (is.list(result)) {")

        for(name in names(outputParams)) {
            if (tolower(outputParams[[name]]) == "dataframe") {
                ending <- c(ending,paste0("  ", name," <- result$", name))
            } else {
                ending <- c(ending,paste0("  ", name, " <- result$", name))
            }
        }
        ending <- c(ending,
                    "} else if (!is.null(result)) {",
                    "  stop(\"the R function must return a list\")"
        )
    }
    ending <- c(ending, "}")
}

# @import RODBC
# Execute the registration script
register <- function(registrationScript, connectionString) {
    output <- character(0)

    tryCatch({
        dbhandle <- odbcDriverConnect(connectionString)
        output <- sqlQuery(dbhandle, registrationScript)
    }, error = function(e) {
        stop(paste0("Error in SQL Execution:\n", e))
    }, finally ={
        odbcCloseAll()
    })
    if (length(output) > 0 ) {
        stop(output)
    }
    output
}
