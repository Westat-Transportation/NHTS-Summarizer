#' Summarize NHTS Data
#' 
#' Create weighted aggregate tables using NHTS data.
#'
#' @param data Object returned by \link[summarizeNHTS]{read_data}.
#' @param agg Aggregate function label. Either "household_count", "person_count", "trip_count", 
#' "sum", "avg", "median", "household_trip_rate", or "person_trip_rate". See \emph{Aggregates} section
#' @param agg_var Character string specifying a numeric variable over which to aggregate. 
#' Only relavent when agg is "avg" or "sum"
#' @param by Character vector of one or more variable names to group by. See \emph{Analysis Groups} section.
#' @param subset Character string containing a pre-aggregation subset condition using \link[data.table]{data.table} syntax.
#' See \emph{Filter} section. 
#' @param label logical. Use labels for table output?
#' @param prop logical. Use proportions for count aggregates?
#' @param prop_by Character vector of one or more variable names by which to group proportions.
#' @param exclude_missing logical. Exclude missing responses from summary.
#' @return data.table object aggregated by input specifications containing the following fields:
#' 
#' \itemize{
#'   \item \code{by} variables. For each \code{by} variable, a column of the same name is created.
#'   They will appear in the order they are listed as \link[base:factor]{factors} ordered by their codebook values.
#'   \item \strong{W} - Weighted statistic.
#'   \item \strong{E} - Standard error of the weighted statistic.
#'   \item \strong{S} - Surveyed/sampled statistic.
#'   \item \strong{N} - Number of observations/sample size.
#' }
#' 
#' @section Aggregates (\code{agg}):
#' What type of aggregate are you interested in?
#' 
#' \subsection{Frequencies / Proportions}{
#'   \itemize{
#'     \item \strong{household_count} - Count of households
#'     \item \strong{person_count} - Count of persons
#'     \item \strong{trip_count} - Count of trips
#'     \item \strong{vehicle_count} - Count of vehicles
#'   }
#'   \emph{*Use} \code{prop = TRUE} \emph{in combination with a count aggregate to get the proportion.}
#' }
#' 
#' \subsection{Numeric Aggregates (Sum / Average / Median)}{
#'   \emph{Must also specify a numeric aggregate variable using the} \code{agg_var} \emph{parameter.}
#'   \itemize{
#'     \item \strong{sum} - Sum of \code{agg_var}
#'     \item \strong{avg} - Arithmetic mean of \code{agg_var}
#'     \item \strong{median} - Median of \code{agg_var}
#'   }
#' }
#' 
#' \subsection{Trip Rates (Daily Person Trips per Person/Household)}{
#'   Simply put, the count of trips divided by the count of persons or households.
#'   \itemize{
#'     \item \strong{household_trip_rate} - Daily trips per household.
#'     \item \strong{person_trip_rate} - Daily trips per person.
#'   }
#' }
#' 
#' @section Analysis Groups (\code{by}):
#' By which variables to you wish to aggregate?
#' 
#' Similar to \code{GROUP BY} in SQL or a \code{CLASS} statement in SAS.
#' There is no limit to the number of variables specified in the character vector, however many \code{by} variables
#' can result in groups with small sample sizes which need to be interpreted carefully.
#' 
#' The data.table returned by summarize_data will include a column (of class \link[base]{factor}) for each \code{by} variable specified.
#' 
#' @section Filtering (\code{subset}):
#' Which households/person/trips do you wish to include or exclude?
#' 
#' Similar to \code{WHERE} in SQL, \code{subset} allows you to filter observations/rows in the dataset before summarizing/aggregating.
#' 
#' \code{subset} is a string that will be evaluated as a logical vector indicating the rows to keep.
#' As mentioned above, the string will be evaluated as the \code{i} index in a \link[data.table]{data.table}.
#' In short, similar to the base function \link[base]{subset},
#' there is no need to specify the data object in which the variables are included
#' (i.e.: your code would look like \code{"var < 10"} instead of \code{"data$var < 10"}).
#' 
#' Any variable (or combination of variables) found in the codebook can be used in the subset condition.
#' See \link[base]{Logic} for a refresher on R's logical operators when using more than one logical condition.
#' 
#' \subsection{Quoting within quotes}{
#' You will frequently need to include quotes in your string. You can tackle this a few different ways.
#' The following examples would all evaluate the same way:
#'   \itemize{
#'     \item \code{"HHSTATE \%in\% c('GA','FL')"}
#'     \item \code{'HHSTATE \%in\% c("GA","FL")'}
#'     \item \code{"HHSTATE \%in\% c(\"GA\",\"FL\")"}
#'   }
#' }
#' 
#' @examples
#' \donttest{
#' # Read 2009 NHTS data with specified csv path:
#' nhts_data <- read_data('2009', csv_path = 'C:/NHTS')
#' 
#' summarize_data(
#'   data = nhts_data,           # Using the nhts_data object,
#'   agg = 'person_trip_rate',   # calculate the person trip rate
#'   by = 'WORKER',              # by worker status
#'   subset = 'CENSUS_R == "01"' # for households in the NE Census region
#' )
#' }
#' 
#' 
#' @export
summarize_data <- function(data, agg, agg_var = NULL, by = NULL, subset = NULL, label = TRUE, prop = FALSE, prop_by = NULL, exclude_missing = FALSE) {
  
  if (!'HTS.data' %in% class(data)) {
    stop('data is not an "HTS.data" object (returned by the read_data function).')
  }
  
  # Get variables from data specified by the dataset attribute
  dataset <- data$dataset
  variables <- CB(dataset)$variables
  
  # If null, set subset to TRUE so that all rows are selected
  if(is.null(subset)) subset <- TRUE
  
  # Only select necessary variables
  data <- trim_input_data(data, variables, by, agg_var, subset)
  
  # Exclude missing values in subset call
  if(exclude_missing == T) {
    subset <- exclude_missing_values(subset, vars = c(agg_var, by))
  } else {
    # Regardless, exclude missing values for numeric variables
    subset <- exclude_missing_values(subset, vars = agg_var)
  }

  # Set ID/Weight variable names
  HHID  <- ID('household')
  PERID <- ID('person')
  TRPID <- ID('trip')
  VEHID <- ID('vehicle')
  HHWT  <- WT('household', dataset)
  PERWT <- WT('person', dataset)
  TRPWT <- WT('trip', dataset)


  ##############################################################################################################
  ## COUNT AGGREGATES
  ##############################################################################################################
  if (agg %in% c('household_count','vehicle_count','person_count','trip_count')) {
    
    #==========================================================================================================#
    # CONFIGURE LEVEL 
    if (agg == 'household_count') {
      weight_table <- copy(data$weights$household)
      weight_names <- HHWT
      level_config <- 'household'
      pkey <- HHID
    } else if (agg == 'vehicle_count') {
      weight_table <- copy(data$weights$household)
      weight_names <- HHWT
      level_config <- c('household','vehicle')
      pkey <- c(HHID, VEHID)
    } else if (agg == 'person_count') {
      weight_table <- copy(data$weights$person)
      weight_names <- PERWT
      level_config <- c('household','person')
      pkey <- c(HHID, PERID)
    } else if (agg == 'trip_count') {
      weight_names <- TRPWT
      weight_table <- get_trip_weights(data, dataset)
      level_config <- c('household','person','trip')
      pkey <- c(HHID, PERID, TRPID)
    }
    
    #==========================================================================================================#
    # Drop groups if there is a level mismatch
    new_groups <- variables[TABLE %in% level_config & NAME %in% by, NAME]
    if (!all(by %in% new_groups) & !is.null(by)) {
      warning('agg: ', agg, '. Removing the following by: ', paste(by[!by %in% new_groups], collapse = ', '))
      by <- if (length(new_groups) == 0) NULL else new_groups
    }
    
    #==========================================================================================================#
    data_table <- Reduce(function(...) merge(..., allow.cartesian = T, all = T, suffixes = c('_duplicate','')), data$data)
    rm(data)
    data_table <- unique(data_table[eval(parse(text = subset)), c(pkey, by), with = F])
    setkeyv(data_table, pkey)
    data_table <- na.omit(data_table[weight_table, nomatch=0])
    
    #==========================================================================================================#
    # Compute weighted counts
    weighted_data <- data_table[, lapply(.SD, sum), by = by, .SDcols = weight_names]
    
    #==========================================================================================================#
    # Compute unweighted counts
    unweighted_data <- data_table[, list(S = .N), by = by]
    
    #==========================================================================================================#
    # Compute proportions
    if (prop == T) {
      weighted_data[, (weight_names) := lapply(.SD, prop.table), by = prop_by, .SDcols = weight_names]
      unweighted_data$S <- as.double(unweighted_data$S)
      unweighted_data[, S := prop.table(S), by = prop_by]
    }
    
    #==========================================================================================================#
    # Count data is same as unweighted data for count aggrergates
    count_data <- data_table[, .N, by = by]
    
    ##############################################################################################################
    ## SUM/AVG AGGREGATES
    ##############################################################################################################
  } else if (agg %in% c('sum','avg','median')) {
    
    #==========================================================================================================#
    agg_level <- variables[NAME == agg_var, TABLE]
    pkey_level <- variables[NAME %in% c(agg_var, by), TABLE]
    
    #==========================================================================================================#
    # CONFIGURE WEIGHTS 
    if (agg_level == 'household') {
      weight_table <- copy(data$weights$household)
      weight_names <- HHWT
      level_config <- c('household')
    } else if (agg_level == 'vehicle') {
      weight_table <- copy(data$weights$household)
      weight_names <- HHWT
      level_config <- c('household','vehicle')
    } else if (agg_level == 'person') {
      weight_table <- copy(data$weights$person)
      weight_names <- PERWT
      level_config <- c('household','person')
    } else if (agg_level == 'trip') {
      weight_names <- TRPWT
      weight_table <- get_trip_weights(data, dataset)
      level_config <- c('household','person','trip')
    }
    
    #==========================================================================================================#
    # CONFIGURE PRIMARY KEY LEVEL
    if (any(pkey_level == 'trip')) {
      pkey <- c(HHID, PERID, TRPID)
    } else if (any(pkey_level == 'person')) {
      pkey <- c(HHID, PERID)
    } else if (any(pkey_level == 'vehicle')) {
      pkey <- c(HHID, VEHID)
    } else if (any(pkey_level == 'household')) {
      pkey <- HHID
    }
    
    #==========================================================================================================#
    # Drop group variables if there is a level mismatch
    new_groups <- variables[TABLE %in% level_config & NAME %in% by, NAME]
    if (!all(by %in% new_groups) & !is.null(by)) {
      warning('agg: ', agg, '. Removing the following by: ', paste(by[!by %in% new_groups], collapse = ', '))
      by <- if (length(new_groups) == 0) NULL else new_groups
    }
    
    #==========================================================================================================#
    data_table <- Reduce(function(...) merge(..., allow.cartesian = T, all = T, suffixes = c('_duplicate','')), data$data)
    rm(data)
    data_table <- unique(data_table[eval(parse(text = subset)), c(pkey, by, agg_var), with = F])
    setkeyv(data_table, pkey)
    data_table <- na.omit(data_table[weight_table, nomatch=0])
    
    #==========================================================================================================#
    # Compute count aggregate
    count_data <- data_table[, .N, by = by]
    
    #==========================================================================================================#
    if (agg == 'sum') {
      
      weighted_data <- data_table[, lapply(.SD, Rcpp_wgtsum, x = get(agg_var)), by = by, .SDcols = weight_names]
      unweighted_data <- data_table[, list(S = sum(get(agg_var))), by = by]
      
    } else if (agg == 'avg') {
      
      weighted_data <- data_table[, lapply(.SD, Rcpp_wgtavg, x = get(agg_var)), by = by, .SDcols = weight_names]
      unweighted_data <- data_table[, list(S = mean(get(agg_var))), by = by]
      
    } else if (agg == 'median') {
      
      weighted_data <- data_table[, lapply(.SD, Rcpp_wgtmed, x = get(agg_var)), by = by, .SDcols = weight_names]
      unweighted_data <- data_table[, list(S = median(get(agg_var))), by = by]
      
    }
    
    ##############################################################################################################
    ## TRIP RATE AGGREGATES
    ##############################################################################################################
  } else if (agg %in% c('household_trip_rate','person_trip_rate')) {
    
    #==========================================================================================================#
    #Grab the names of the variables that are not at the trip level
    non_trip_groups <- variables[NAME %in% by & !TABLE %in% c('trip'), NAME]
    trip_groups <- by[!by %in% non_trip_groups]
    
    #==========================================================================================================#
    # CONFIGURE TRIP RATE LEVEL - Household or Person trip rates
    if (agg == 'household_trip_rate') {
      weight_table <- copy(data$weights$household)
      weight_names <- HHWT
      pkey <- HHID
    } else if (agg == 'person_trip_rate') {
      weight_table <- copy(data$weights$person)
      weight_names <- PERWT
      pkey <- c(HHID, PERID)
    }
    
    #==========================================================================================================#
    # Get trip weight names
    trip_weight_names <- TRPWT
    
    #==========================================================================================================#
    # Merge all data.tables
    data_table <- Reduce(function(...) merge(..., allow.cartesian = T, all = T, suffixes = c('_duplicate','')), data$data)
    
    #==========================================================================================================#
    # Denominator - Household or Person Count
    pkey_distinct <- unique(data_table[eval(parse(text = subset)), c(pkey, non_trip_groups), with = F])
    pkey_weights <- merge(pkey_distinct, weight_table, by = pkey)
    pkey_count <- pkey_weights[, lapply(.SD, sum), keyby = non_trip_groups, .SDcols = weight_names]
    unweighted_pkey_count <- pkey_distinct[, .N, keyby = non_trip_groups]
    rm(pkey_distinct, pkey_weights)
    
    #==========================================================================================================#
    # Numerator - Trip Count
    trip_distinct <- na.omit(unique(data_table[eval(parse(text = subset)), c(HHID, PERID, TRPID, by), with = F]))
    trip_weights <- merge(trip_distinct, get_trip_weights(data, dataset), by = c(HHID, PERID, TRPID))
    trip_count <- trip_weights[, lapply(.SD, sum), keyby = by, .SDcols = trip_weight_names]
    unweighted_trip_count <- trip_distinct[, .N, keyby = by]
    rm(data_table, trip_weights, data)
    
    #==========================================================================================================#
    # Sample Count
    count_data <- trip_distinct[, .N, by = by]
    rm(trip_distinct)
    
    #==========================================================================================================#
    # weighted calculations
    if (length(non_trip_groups) > 0) {
      weighted_counts <- merge(trip_count, pkey_count)
    } else {
      weighted_counts <- cbind(trip_count, pkey_count)
    }
    
    #==========================================================================================================#
    # Element-wise division of trip_weights over pkey_weights
    weighted_trip_rates <- weighted_counts[, ..trip_weight_names] / weighted_counts[, ..weight_names]
    weighted_trip_rates <- weighted_trip_rates / getOption('HTS.annualized.days') # Divide to get Daily rates
    colnames(weighted_trip_rates) <- weight_names
    
    #==========================================================================================================#
    # Append group variables to weighted data if they exist
    if (!is.null(by)) {
      weighted_data <- cbind(weighted_counts[,..by], weighted_trip_rates)
    } else {
      weighted_data <- weighted_trip_rates
    }
    
    #==========================================================================================================#
    # unweighted calculations
    if (length(non_trip_groups) > 0) {
      unweighted_counts <- merge(unweighted_trip_count, unweighted_pkey_count, suffixes = c('_trip','_pkey'))
    } else {
      setnames(unweighted_pkey_count, 'N', 'N_pkey')
      setnames(unweighted_trip_count, 'N', 'N_trip')
      unweighted_counts <- cbind(unweighted_trip_count, unweighted_pkey_count)
    }
    unweighted_data <- unweighted_counts[, .(S = N_trip / N_pkey), keyby = by]
    
    
  } else {
    stop(agg,' is not a valid aggregate label. Use "household_count", "vehicle_count", ',
    '"person_count", "trip_count", "sum", "avg", "household_trip_rate", or "person_trip_rate".')
  }
  
  ################################################################################################################
  
  #==========================================================================================================#
  # Compute Standard Error (E)
  fin_wgt <- as.matrix(weighted_data[, weight_names[1], with=F])
  rep_wgt <- as.matrix(weighted_data[, weight_names[-1], with=F])
  E <- jk_se(fin_wgt, rep_wgt, dataset)
  
  #==========================================================================================================#
  # Merge weighted (W), error (E), sampled/unweighted (S), and count (N) data
  weighted_data <- cbind(weighted_data[, !weight_names[-1], with = F], E)
  
  setkeyv(weighted_data, by)
  setkeyv(unweighted_data, by)
  setkeyv(count_data, by)
  
  if (!is.null(by)) {
    tbl <- Reduce(merge, list(weighted_data, unweighted_data, count_data))
  } else {
    tbl <- cbind(weighted_data, unweighted_data, count_data)
  }
  
  # Set column names and group variable order
  setnames(tbl, weight_names[1], 'W')
  setorderv(tbl, by)
  
  # Warn if prop = T with non-count aggregates
  if (prop == T & !agg %in% c('household_count','vehicle_count','person_count','trip_count')) {
    warning('Can only calculate proportions for count aggregates. Ignoring parameter "prop = TRUE".')
  }
  
  ##############################################################################################################
  # Set Table Attributes
  ##############################################################################################################
  
  setattr(tbl, 'dataset', dataset)
  setattr(tbl, 'agg', agg)
  setattr(tbl, 'agg_var', agg_var)
  setattr(tbl, 'agg_var_label', variables[NAME %in% agg_var, LABEL])
  setattr(tbl, 'by', by)
  setattr(tbl, 'error', 'Standard Error')
  setattr(tbl, 'prop', prop)
  setattr(tbl, 'label', label)
  setattr(tbl, 'agg_label', switch(agg, 
    household_count = 'Household Frequency',
    vehicle_count = 'Vehicle Frequency',
    person_count = 'Person Frequency',
    trip_count = 'Trip Frequency',
    sum = 'Sum',
    avg = 'Average',
    median = 'Median',
    person_trip_rate = 'Person Trip Rate',
    household_trip_rate = 'Household Trip Rate'
  ))
  if (!is.null(by)) {
    setattr(tbl, 'by_label', as.list(
      variables[NAME %in% by, mapply(function(x,y) cbind(x = y), x = NAME, y = LABEL)]
    ))
  } else {
    setattr(tbl, 'by_label', list())
  }
  
  ##############################################################################################################
  
  # Assign labels to tabke if label parameter is TRUE
  if (label == T) tbl <- use_labels(tbl, dataset)
  
  if (!is.null(by)) {
    # Make sure data.table key is set to the table by if present
    setkeyv(tbl, by)
    # Coerce group variables as factors
    tbl[, (by):= lapply(.SD, factor), .SDcols=by]
  }
  
  # Assign S3 class to table
  class(tbl) <- c(class(tbl), 'HTS.summary.table')
  
  # Garbage collection
  invisible(gc()) 
  
  return(tbl[])
}

