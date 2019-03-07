# ETL Script for loading aggregated demographic data from US Census Summary File.
 
This script extracts and aggregates demographic metrics from the 2010 US Census Summary File 1. My goal was to create JSON objects to display total populations grouped by age, gender, and race for each area of interest. Once I obtained the following form JSON, I exported the JSON objects to MongoDB. 

Sample JSON object:    
```json  [  
    {  
    "_id" : "asdfasdfa102838",  
    "LOGRECNO" : "000023445",  
    "FIPS" : "55025",  
    "name" : "Dane County",  
    "age" : "15-17",  
    "sex" : "Male",  
    "race" : "Asian",  
    "count" : 26541,  
    }  
];  
```

The script is flexible and will obtain data for any state, county, subcounty/place with some minor adjustments. For sake of simplicity and processing time I decided to only obtain county level data within Wisconsin. From there I exported all the demographic data for a single county (Dane County).
