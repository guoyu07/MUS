# calculate maximal number of wrong items in the population, given the sample, additionally alpha=1-confidence level
.calculate.m.hyper <- function(error.taintings, sample.size, alpha, account.value) {

	if (error.taintings==sample.size) return(Inf) # uniroot will not find a solution in that case because the probability is constant at 1. Thus, the situation has to be prevented.

	# function that sums up the probabilities for each error and calculate the deviance to the given confidence level
	calculate.deviance <- function (wrong.units) {
		phyper(q=error.taintings, m=wrong.units, n=(account.value-wrong.units), k=sample.size)-alpha
	}

	# search the zero point of the deviance and return the ceiled value
	return(ceiling(uniroot(calculate.deviance, c(0, account.value))$root))
}


# create a table, based on the ideas of precision gap widening and cell evaluation
.MUS.precision.gap.widening.table <- function(ds, population.amount, confidence.level, filled.sample){
	# UEL Factor = lambda = E(distribution) = Sample size * Errors in Population / Elements in population
	UEL.Factor <- round(sapply(0:length(ds), .calculate.m.hyper, sample.size=nrow(filled.sample), alpha=1-confidence.level, account.value=population.amount)*nrow(filled.sample)/population.amount, digits=4)
	average.ds <- round(cumsum(ds)/1:length(ds), digits=4)
	
	# create table
	result.table <- data.frame(Error.Stage=0:length(ds), UEL.Factor=UEL.Factor, Tainting=c(1,ds), Average.Taintings=c(0,average.ds), UEL.previous.Stage=rep(0, times=length(UEL.Factor)), Load.and.Spread=rep(0, times=length(UEL.Factor)), Simple.Spread=c(UEL.Factor[1], rep(NA, times=length(UEL.Factor)-1)), Stage.UEL.max=c(UEL.Factor[1], rep(NA, times=length(UEL.Factor)-1)))
	if (length(ds)==0) return(result.table) # stop to prevent errors if no errors are found
	# fill last 4 columns (row by row, because the next row is dependent of values of the previous row)
	for (row in (1:length(ds))+1){ # for each Error.Stage, because first row with 0 taintings is always +1
		result.table$UEL.previous.Stage[row] <- result.table$Stage.UEL.max[row-1]
		result.table$Load.and.Spread[row] <- result.table$UEL.previous.Stage[row]+result.table$Tainting[row]
		result.table$Simple.Spread[row] <- result.table$UEL.Factor[row]*result.table$Average.Taintings[row]
		result.table$Stage.UEL.max[row] <- max(result.table$Load.and.Spread[row], result.table$Simple.Spread[row])
	}
	return(result.table)
}


MUS.evaluation <- function(extract, filled.sample, filled.high.values, col.name.audit.values="audit.value", col.name.riskweights=NULL){
	# checking parameter extract, col.name.audit.values and col.name.riskweights
	if (class(extract)!="MUS.extraction.result") stop("extract has to be an object from type MUS.extraction.result. Use function MUS.extraction to create such an object.")
	if (!is.character(col.name.audit.values) | length(col.name.audit.values)!=1) stop("col.name.audit.values has to be a single character value (default book.value).")
		if (!is.null(col.name.riskweights)) if (!is.character(col.name.riskweights) | length(col.name.riskweights)!=1) stop("col.name.riskweights has to be NULL if no risk weights are used (as in ordinary MUS) or a single character value (default NULL).")

	# if extracted sample has no elements (only high value items needs to be tested) do not evaluate and use zeros instead
	if (nrow(extract$sample)==0) {
		Results.Sample <- list( Sample.Size=0,
					Number.of.Errors=c(overstatements=0, understatements=0), 
					Gross.most.likely.error=0,
					Net.most.likely.error=c(overstatements=0, understatements=0),
					Basic.Precision=0,
					Precision.Gap.widening=c(overstatements=0, understatements=0),
					Total.Precision=c(overstatements=0, understatements=0),
					Gross.upper.error.limit=c(overstatements=0, understatements=0),
					Net.upper.error.limit=0)
		filled.sample <- "Not required because no sample items were selected during extraction"
		over <- "Not applicable because no sample items were selected during extraction"
		under <- "Not applicable because no sample items were selected during extraction"	  
	} else {
		# check parameters filled.sample in combination with col.name.book.values, col.name.audit.values and col.name.riskweights
		if (!is.data.frame(filled.sample) | is.matrix(filled.sample)) stop("filled.sample needs to be a data frame or a matrix but it is not.")
		if (!is.element(extract$col.name.book.values, names(filled.sample))) stop("The filled.sample requires a column with the book values and the name of this column has to be provided by parameter col.name.book.values during MUS.planning (default book.value).")
		if (!is.element(col.name.audit.values, names(filled.sample))) stop("The filled.sample requires a column with the audit values and the name of this column has to be provided by parameter col.name.audit.values (default audit.value).")
		if (!is.null(col.name.riskweights)) if(!is.element(col.name.riskweights, names(filled.sample))) stop("If col.name.riskweights is not NULL, the filled.sample requires a column with the col.name.riskweights and the name of this column has to be provided by parameter col.name.riskweights (default NULL).")

		# evaluate sample
		population.amount <- sum(extract$sample.population[,extract$col.name.book.values])

		# prevent Errors if column name will not be unique (a column d is used in over- and understatement evaluation)
		if(is.element("d", names(filled.sample))) stop("filled.sample must not have a column 'd' because this column name is used for internal evaluation.") 

		# calculate suitable d's und evaluation table - overstatements
		ds <- cbind(filled.sample, d=1-filled.sample[,col.name.audit.values]/filled.sample[,extract$col.name.book.values]) # calculate d's and add to data frame
		ds <- subset(ds, ds$d>0) # filter out all correct (and understatements which will be handled later)
		ds <- ds[order(ds$d,decreasing=TRUE),] # sort d's descendend
		if(is.null(col.name.riskweights)) {
			ds <- ds$d
		} else {
			ds <- ds$d/ds[,col.name.riskweights] # if risk weights are provided, also multiply with them
		}
		ds <- round(ds, digits=4)
		over <- .MUS.precision.gap.widening.table(ds, population.amount, extract$confidence.level, filled.sample) # calculate table
		
		# calculate suitable d's und evaluation table - understatements
		ds <- cbind(filled.sample, d=1-filled.sample[,col.name.audit.values]/filled.sample[,extract$col.name.book.values]) # calculate d's and add to data frame
		ds <- subset(ds, ds$d<0) # filter out all correct (and overstatements which was handled before)
		ds <- ds[order(ds$d,decreasing=FALSE),] # sort d's ascendend
		if(is.null(col.name.riskweights)) {
			ds <- -ds$d
		} else {
			ds <- -ds$d/ds[,col.name.riskweights] # if risk weights are provided, also multiply with them
		}
		ds <- round(ds, digits=4)
		under <- .MUS.precision.gap.widening.table(ds, population.amount, extract$confidence.level, filled.sample) # calculate table

		# calculate results table
		Gross.most.likely.error=c(overstatements=(sum(over$Tainting)-1), understatements=(sum(under$Tainting)-1))*extract$sampling.interval # also required as intermediate step for later calculations
		Gross.upper.error.limit=c(overstatements=max(over$Stage.UEL.max), understatements=max(under$Stage.UEL.max))*extract$sampling.interval # also required as intermediate step for later calculations
		Basic.Precision=.calculate.m.hyper(0, sample.size=nrow(filled.sample), alpha=1-extract$confidence.level, account.value=population.amount) # also required as intermediate step for later calculations
		Results.Sample <- list( Sample.Size=nrow(filled.sample), 
					Number.of.Errors=c(overstatements=max(over$Error.Stage), understatements=max(under$Error.Stage)), 
					Gross.most.likely.error=Gross.most.likely.error,
					Net.most.likely.error=c(overstatements=1, understatements=-1)*sum(Gross.most.likely.error*c(1,-1)),
					Basic.Precision=Basic.Precision,
					Precision.Gap.widening=Gross.upper.error.limit-Gross.most.likely.error-Basic.Precision, # values that are not zero came from rounding
					Total.Precision=Gross.upper.error.limit-Gross.most.likely.error,
					Gross.upper.error.limit=Gross.upper.error.limit,
					Net.upper.error.limit=Gross.upper.error.limit-Gross.most.likely.error+c(overstatements=1, understatements=-1)*sum(Gross.most.likely.error*c(1,-1)))
	}

	# if extracted high items have no elements (only sample items needs to be tested) do not evaluate and use zeros instead
	if (nrow(extract$high.values)==0) {
		Results.High.values <- list(Number.of.high.value.items=0,
					    Number.of.Errors=c(overstatements=0, understatements=0),
					    Gross.Value.of.Errors=c(overstatements=0, understatements=0),
					    Net.Value.of.Errors=0)
		filled.high.values <- "Not required because no high value items were selected during extraction."

	} else {

	# check parameters filled.high.values in combination with col.name.book.values, col.name.audit.values and col.name.riskweights
	if (!is.data.frame(filled.high.values) | is.matrix(filled.high.values)) stop("filled.high.values needs to be a data frame or a matrix but it is not.")
	if (!is.element(extract$col.name.book.values, names(filled.high.values))) stop("The filled.high.values requires a column with the book values and the name of this column has to be provided by parameter col.name.book.values during MUS.planning (default book.value).")
	if (!is.element(col.name.audit.values, names(filled.high.values))) stop("The filled.high.values requires a column with the audit values and the name of this column has to be provided by parameter col.name.audit.values (default audit.value).")
	if (!is.null(col.name.riskweights)) if (!is.element(col.name.riskweights, names(filled.high.values))) stop("If col.name.riskweights is not NULL, the filled.high.values requires a column with the col.name.riskweights and the name of this column has to be provided by parameter col.name.riskweights (default NULL).")

	
	# evaluate high value items
		errors <- filled.high.values[,extract$col.name.book.values]-filled.high.values[,col.name.audit.values]
		if(is.null(col.name.riskweights)) {
			errors <- filled.high.values[,extract$col.name.book.values]-filled.high.values[,col.name.audit.values]
		} else {
			errors <- (filled.high.values[,extract$col.name.book.values]-filled.high.values[,col.name.audit.values])/filled.high.values[,col.name.riskweights] # if risk weights are provided, also multiply with them
		}
		Results.High.values <- list(Number.of.high.value.items=nrow(filled.high.values),
					    Number.of.Errors=c(overstatements=sum(errors>0), understatements=sum(errors<0)),
					    Gross.Value.of.Errors=c(overstatements=sum(subset(errors, errors>0)), understatements=sum(subset(errors, errors<0))),
					    Net.Value.of.Errors=sum(errors))
	}
		
	# evaluate sample and high values combined
	Results.Total <- list(  Total.number.of.items.examined=Results.Sample$Sample.Size+Results.High.values$Number.of.high.value.items, 
				Number.of.Errors=Results.Sample$Number.of.Errors+Results.High.values$Number.of.Errors, 
				Gross.most.likely.error=Results.Sample$Gross.most.likely.error+Results.High.values$Gross.Value.of.Errors,
				Net.most.likely.error=c(overstatements=1, understatements=-1)*sum(Results.Sample$Gross.most.likely.error)+Results.High.values$Net.Value.of.Errors*c(1,-1),
				Gross.upper.error.limit=Results.Sample$Gross.upper.error.limit+Results.High.values$Gross.Value.of.Errors,
				Net.upper.error.limit=Results.Sample$Gross.upper.error.limit-Results.Sample$Gross.most.likely.error+c(overstatements=1, understatements=-1)*sum(Results.Sample$Gross.most.likely.error*c(1,-1))+Results.High.values$Net.Value.of.Errors*c(1,-1))

	# extract a final statement if population is acceptable (provided the confidence level)
	acceptable <- max(Results.Total$Net.upper.error.limit*c(1,-1))<extract$tolerable.error

	# gives warning if high error rate evaluation might be appropriate
	if (max(Results.Sample$Number.of.Errors)>=20) {
		warning("You had at least 20 errors in the sample - some statistical software recommends High Error Rate evaluation instead of Low Error Rate evaluation in this case. However, High Error Rate evaluation is not yet implemented. The evaluation might not be appropriate.")
	}

	# return all results and parameters
	result <- c(extract, list(filled.sample=filled.sample, filled.high.values=filled.high.values, col.name.audit.values=col.name.audit.values, Overstatements.Result.Details=over, Understatements.Result.Details=under, Results.Sample=Results.Sample, Results.High.values=Results.High.values, Results.Total=Results.Total, acceptable=acceptable))
	class(result) <- "MUS.evaluation.result"
	return(result)
}