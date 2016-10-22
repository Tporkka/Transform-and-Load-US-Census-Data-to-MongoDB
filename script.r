
#This script obtains demographic data from the 2010 census summary file 1. 
#The end goal is creating bson documents to upload into mongo db with
#population counts by age,race,and sex for each area. For now I'll stick with
#the county level to keep things simple. 

#Note: You will need mdbtools installed on your computer.

#load packages, set working directory, and load data:
suppressMessages(library(dplyr))
library(RCurl)
library(readr)
library(Hmisc)#using mdb.get from here.
library(magrittr)#use %<>% from here
library(stringr)


root <- "~/Desktop" #change if you'd like. 
remotePath <- "http://www2.census.gov/census_2010/04-Summary_File_1/"
setwd(root)

# data from http://www2.census.gov/census_2010/04-Summary_File_1/Wisconsin/wi2010.sf1.zip

#select state and create new folder for that state's data. 
state <- "Wisconsin"
abb <- "wi"#to do: automate this later to abbreviate each state instead of hand labelling. 
if(!dir.exists("summary-files")) dir.create("summary-files")
setwd("summary-files")

if(!dir.exists(state)) dir.create(state)
setwd(state)

temp <- tempfile()
if(!file.exists("wi000012010.sf1")) {#download and unzip files if not already in directory
    download.file(paste0(remotePath, state,"/", paste0(abb,"2010.sf1.zip")),
                                                           destfile = temp, quiet = TRUE, method = "curl")
    unzip(temp)
    }
#now all state demographic files should be in working directory.     
#PCT12 contains all age,sex,and race totals in summary file 1.
    

#Obtain Feature Labels from MS Access files:
if(!file.exists("SF1_Access2003.mdb")) download.file("http://www2.census.gov/census_2010/04-Summary_File_1/SF1_Access2003.mdb",
              destfile = "SF1_Access2003.mdb",quiet=TRUE,method="curl")
if(!file.exists("DPSF2010_Access2003.mdb")) download.file("http://www2.census.gov/census_2010/03-Demographic_Profile/DPSF2010_Access2003.mdb",
              destfile = "DPSF2010_Access2003.mdb",quiet=TRUE,method="curl")
    
mdb.get("SF1_Access2003.mdb",tables="DATA_FIELD_DESCRIPTORS") -> descriptions #names corresponding to demographic headers.
mdb.get("SF1_Access2003.mdb",tables="SF1_00001") -> demHeader
mdb.get("SF1_Access2003.mdb",tables="SF1_00007mod") -> demNames_07 #These contain all of the demographic headers down to 
mdb.get("SF1_Access2003.mdb",tables="SF1_00008mod") -> demNames_08 ##the block level
mdb.get("DPSF2010_Access2003.mdb", tables="Header") -> geoHeaders #contains length and names for geographic variables
dem07 <- cbind(demHeader[1:4], demNames_07)
dem08 <- cbind(demHeader[1:4], demNames_08)
##Uncomment below to see the nature of the initial data. 
#summary(descriptions)
#head(dem07)
#head(dem08)
head(geoHeaders)

#Merge headers to data files and select county level data:

sf_07 <- paste0(abb,"000072010.sf1") %>% read_csv(col_names=FALSE,
                                          col_types = cols(.default = col_character()))
sf_08 <- paste0(abb,"000082010.sf1") %>% read_csv(col_names=FALSE,
                                          col_types = cols(.default = col_character()))
geoData <- read_fwf(paste0(abb, "geo2010.sf1"), fwf_widths(geoHeaders$LEN,col_names=as.character(geoHeaders$NAME)),
                                          col_types = cols(.default = col_character()))

#county level data
geo <- geoData %>% filter(SUMLEV=="050")
#head(geo)

#Select geographic features and rename demographic variables to match Summary File Keys: 

geo1 <- geo %>% select(STUSAB, SUMLEV, GEOCOMP, LOGRECNO, STATE, COUNTY, COUNTYCC, NAME)
names(sf_07) <- names(dem07)
names(sf_08) <- names(dem08)
#head(sf_07)

library(data.table)
sfa <- data.table(sf_07, key="LOGRECNO")
sfb <- data.table(sf_08, key="LOGRECNO")
geo_table <- data.table(geo1, key = "LOGRECNO")
#head(geo_table)



#Merge all data tables to single dataframe:

dt3 <- merge(geo_table, sfa, all.x = TRUE)
dt4 <- merge(dt3, sfb, all.x=TRUE)

#convert back to dataframe to subset using grep. 
df1 <- data.frame(dt4)
df2 <- df1[,c(1:8, grep("^P012[A-I].*", colnames(df1)))]
#head(df2)


#Functions for labelling demographic features:

library(gsubfn)

desc <- descriptions 

getRace <- function(col){
    string <- col
    table <- gsub(string, substr(string, 1, 5), string) #"table" variable refers to table column name in description file
    table1 <- gsub("0", "", table) #cleaned string to match table id format
    race <- as.character(desc$FIELD.NAME[desc$TABLE == table1][1])
    race1 <- strapplyc(race, "\\((.*)\\)", simplify = TRUE)
    return(race1)
}
    
getAge <- function(col){
    string <- desc$FIELD.NAME[desc$FIELD.CODE == col]
    if(grepl("years", string)){
        age1 <- sub(" (years)", "", string)
        age2 <- sub(" to ", "-", age1)
        age <- trimws(age2, which = c("both","left","right"))
        }
    if(grepl("^ *Male:", string)) age <- "ALL"
    if(grepl("^ *Female:", string)) age <- "ALL" 
    if(grepl("^Total:", string)) age <- "ALL"
    return(age)
}

getSex <- function(col){
    num <- as.numeric(strapplyc(col, "^P012[A-I]0([0-4][0-9])", simplify = TRUE))
    if(num > 1 & num < 26) sex <- "MALE"
    if(num >= 26 & num <= 49) sex <- "FEMALE"
    if(num == 1) sex <- "TOTAL"
    return(sex) 
}


#Initialize a MongoDB instance and define importing function:
library(rmongodb)
db <- mongo.create(host = "localhost")
mongo.is.connected(db)
ns <- "test.CountyDemographics4"

importToMongo <- function(doc){
    mongo.insert(db, ns, doc)
}

#Creating a Labelled JSON file:
##here we need to classify the variable names (ex. P012002 --> White, Female, age 5-9) by using the "descriptions" file. 
##and then attach the value associated with each demographic group to the final JSON object. 

cnty <- df2

for(r in 1:nrow(cnty)) {
    LOGRECNO <- cnty$LOGRECNO[r]
    STUSAB <- cnty$STUSAB[r]
    SUMLEV <- cnty$SUMLEV[r]
    STATE <- cnty$STATE[r]
    COUNTY <- cnty$COUNTY[r]
    NAME <- cnty$NAME[r]
    FIPS <- paste0(STATE, COUNTY)
    
    for(cc in 9:ncol(cnty)) {
        AGE <- getAge(colnames(cnty[cc]))
        SEX <- getSex(colnames(cnty[cc]))
        RACE <- getRace(colnames(cnty[cc]))
        count <- as.factor(cnty[r,cc])
        #write_JSON(LOGRECNO, STUSAB, SUMLEV, STATE, COUNTY, FIPS, NAME, AGE, SEX, RACE, count)
        
        json_elements = sprintf('{"LOGRECNO":"%s",\n "NAME":"%s",\n "STUSAB": "%s",\n "SUMLEV": "%s", \n "STATE":"%s",\n "COUNTY":"%s",\n "FIPS":"%s",\n "AGE": "%s" ,\n "SEX":"%s",\n "RACE":"%s",\n "COUNT": %s}'
     , LOGRECNO, NAME, STUSAB, SUMLEV, STATE, COUNTY, FIPS, AGE, SEX, RACE, count)
       
        bson_object <- mongo.bson.from.JSON(json_elements)
        if(r < 2 & cc < 10) print(bson_object)
        importToMongo(bson_object)
    next
    }
next
}

mongo.count(db, ns)#shows how many documents were imported to MongoDb. 
