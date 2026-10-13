# import libraries
library(tidyverse)
library(rio)


# import data from Stanford database
sequence_summary <- import("sequenceSummaries.csv")
resistance_summary <- import("resistanceSummaries.csv")

# cleaning variable names
sequence_summary <- janitor::clean_names(sequence_summary)
resistance_summary <-janitor::clean_names(resistance_summary)

#removing variables with _level in name for resistance summary data set
resistance_summary <- resistance_summary %>% select(-contains('_level'))
sequence_summary <- sequence_summary %>% select("sequence_name", "genes", "pr_start", 
                                                "pr_end", "rt_start", "rt_end", "in_start",
                                                "in_end", "subtype_percent" ) # selecting variables from sequence summary
report_data <- resistance_summary %>% 
  inner_join(sequence_summary, by = "sequence_name")

