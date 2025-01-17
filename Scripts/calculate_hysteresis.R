# Calculate the hysteresis and flushing indices based on Vaughan et al. 2017 (WRR)
# We are going to use the smoothed P time series for hysteresis (simple moving average over 9 rows; 9 * 15 min = 135 min or 2.25 hrs)
# The data were prepared in compile_calculate_allVars.R

# To do:
  # Re-do these calculations with smoothed P data


# Load packages
 library("tidyverse")
 library("lubridate")
 library("data.table")
 library("zoo")
 
# Read in data ----
  # Compiled 2017-2019 N, P, & Q data from NEWRnet sites
  # The data are from/prepared in compile_calculate_allVars.R
  alldata <- read_csv("Data/streamData_HF_WD_2017-2019.csv", col_types = cols(rain_start = col_datetime(format = ""),
                                                                               event_start = col_datetime(format = ""),
                                                                               falling_inf_pt = col_datetime(format = ""),
                                                                               event_end = col_datetime(format = ""))) %>% 
    # Convert date
    mutate(timestamp = ymd_hms(timestamp, tz = "Etc/GMT+4"),
           rain_start = ymd_hms(rain_start, tz = "Etc/GMT+4"),
           event_start = ymd_hms(event_start, tz = "Etc/GMT+4"),
           falling_inf_pt = ymd_hms(falling_inf_pt, tz = "Etc/GMT+4"),
           event_end = ymd_hms(event_end, tz = "Etc/GMT+4")) %>% 
    # Simplify analyte names from mg/L to just chem. abbrev.
    # rename(NO3 = NO3_mgNL, TP = TP_mgPL, TDP = TDP_mgPL, SRP = SRP_mgPL, PP = PP_mgPL,
    #        # These are the 9-row (135 min) moving averages
    #        TP_ma9 = TP_mgPL_ma9, TDP_ma9 = TDP_mgPL_ma9, SRP_ma9 = SRP_mgPL_ma9, PP_ma9 = PP_mgPL_ma9) %>% 
    # Simplify q_cms to just q
    rename(q = q_cms) %>%
    # In the compile_calculate_allVars.R script, I had done extra interpolation on missing solute data that 
    # is OK for yield calculations, but not for calculating hysteresis indices; here I replace the unsuitable
    # interpolated data with NA
    mutate_at(vars(NO3:PP),
              list(~ ifelse((site == "Hungerford" & (timestamp >= ymd_hms("2018-04-26 04:15:00", tz = "Etc/GMT+4") & timestamp <= ymd_hms("2018-04-26 13:45:00", tz = "Etc/GMT+4"))) |
                              (site == "Wade" & (timestamp >= ymd_hms("2017-10-26 20:45:00", tz = "Etc/GMT+4") & timestamp <= ymd_hms("2017-10-26 22:45:00", tz = "Etc/GMT+4"))) |
                              (site == "Wade" & (timestamp >= ymd_hms("2017-10-27 06:30:00", tz = "Etc/GMT+4") & timestamp <= ymd_hms("2017-10-28 16:30:00", tz = "Etc/GMT+4"))),
                            NA, .))) %>% 
    # These were also bad for turbidity (the time chunks above had turb data [different sensors])
    mutate(turb = ifelse((site == "Wade" & (timestamp >= ymd_hms("2017-10-27 06:30:00", tz = "Etc/GMT+4") & timestamp <= ymd_hms("2017-10-28 16:30:00", tz = "Etc/GMT+4"))) |
                          (site == "Wade" & (timestamp >= ymd_hms("2018-10-10 11:15:00", tz = "Etc/GMT+4") & timestamp <= ymd_hms("2018-10-11 09:15:00", tz = "Etc/GMT+4"))),
                         NA, turb)) %>% 
    # Smooth the P time series using a simple moving average over 9 rows; 9 * 15 min = 135 min or 2.25 hrs
    # http://uc-r.github.io/ts_moving_averages
    arrange(site, timestamp) %>%
    group_by(site, year) %>% 
    mutate_at(vars(c(TP, TDP, SRP, PP)),
              .funs = list("ma9" = ~rollmean(., k = 9, fill = NA))) %>% 
    ungroup() %>% 
    # # Filter rows without chemistry
    # filter(!is.na(NO3)) %>% 
    # Add a condition column, i.e., event vs. baseflow
    # mutate(condition = ifelse(is.na(eventid), "baseflow", "event")) %>% 
    # Add a year column
    # mutate(year = year(timestamp)) %>% 
    # Rearrange columns
    # select(site, timestamp, year, condition, rain_start:event_end, q, NO3:PP, TP_ma9:PP_ma9)
    select(site, timestamp, year, condition, rain_start:event_end, q, turb, NO3:PP, TP_ma9:PP_ma9)

  

# Prepare the data ----
  # Look at event data only
  eventdata <- alldata %>% 
    filter(condition == "event") %>% 
    # Keep only necessary columns
    # select(site, timestamp, event_start, event_end, q, NO3, TP_ma9, TDP_ma9, SRP_ma9, PP_ma9) %>% 
    select(site, timestamp, event_start, event_end, q, turb, NO3, SRP_ma9) %>% 
    # Try removing rows with no Q
    filter(!is.na(q))
  
  # # Examine individual storm
  # test <- eventdata %>% 
  #   filter(site == "Wade" & event_start >= ymd_hms("2015-08-21 03:15:00", tz = "Etc/GMT-4"))
  
  # Graph a single event
  # eventdata %>%
  #   filter(site == "Wade" & event_start == ymd_hms("2017-10-24 16:15:00", tz = "Etc/GMT-4")) %>%
  #   gather(key = "var", value = "val", c(q, SRP)) %>%
  #   ggplot(aes(x = timestamp, y = val)) +
  #   geom_point() +
  #   facet_wrap(~var, ncol = 1, scales = "free_y")
  
  # Create Q sequence onto which we'll interpolate later
  q_step <- eventdata %>% select(site, event_start, event_end)
    # Check to see how many unique site + storms there are
    # howmany <- q_step %>% group_by(site, event_start) %>% summarize(count = n())
  # q_step <- setDT(q_step)[, list(q = seq(from = 0, to = 1, by = 0.01)), by = c("site", "event_start", "event_end")]
  # Using mutate(q = q/100) below because creating a vector using by = 0.01 resulted in floating point precision problems later in the script
  # https://stackoverflow.com/questions/55956654/when-i-use-dplyrfilter-and-a-sequence-command-it-randomly-skips-rows-it-should/55958991#55958991
  q_step <- setDT(q_step)[, list(q = seq(from = 0, to = 100)), by = c("site", "event_start", "event_end")] %>% 
    mutate(q = q/100)
  
  
  # Slice the data on the rising limb of each storm
  # If a solute concentration doesn't change during a storm, e.g., when NO3 is at MDL, the normalization will produce NaN (can't devide by 0)
  hyst_rise <- eventdata %>% 
    # Normalize (between 0 and 1) Q and solutes
    group_by(site, event_start) %>% 
    # mutate(q_norm = (q - min(q)) / (max(q) - min(q))) %>% 
    # mutate_at(vars(c(q, NO3, TP_ma9, TDP_ma9, SRP_ma9, PP_ma9)),
    #           .funs = list(~ (. - min(.)) / (max(.) - min(.)))) %>%
    mutate_at(vars(c(q, turb, NO3, SRP_ma9)),
              .funs = list(~ (. - min(.)) / (max(.) - min(.)))) %>%
    # Arrange data by site and timestamp for the slice below
    arrange(site, timestamp) %>% 
    # Slice data from start of storm to max q
    slice(1:which.max(q)) %>% 
    select(-timestamp) %>% 
    ungroup()

  # Slice the data on the falling limb of each storm 
  hyst_fall <- eventdata %>% 
    group_by(site, event_start) %>% 
    # mutate_at(vars(c(q, NO3, TP_ma9, TDP_ma9, SRP_ma9, PP_ma9)),
    #           .funs = list(~ (. - min(.)) / (max(.) - min(.)))) %>%
    mutate_at(vars(c(q, turb, turb, NO3, SRP_ma9)),
              .funs = list(~ (. - min(.)) / (max(.) - min(.)))) %>%
    arrange(site, timestamp) %>% 
    # Select rows from max Q to end of the storm
    slice(which.max(q):length(q)) %>% 
    # Slice again, this time from max Q to the first minimum Q for the storm
    slice(1:which.min(q)) %>%
    select(-timestamp) %>% 
    ungroup()

    
  # 1. Join the q_step to hyst_rise & hyst_fall
  # 2. Interpolate missing normalized solute values
    # Convert q_step, hyst_rise & hyst_fall to DT's and set the keys to join on
    setDT(q_step)
    setkey(q_step, site, event_start, event_end, q)
    setDT(hyst_rise)
    setkey(hyst_rise, site, event_start, event_end, q)
    setDT(hyst_fall)
    setkey(hyst_fall, site, event_start, event_end, q)
          
    hyst_rise <- 
      # Join with q_step & sort data
      merge(hyst_rise, q_step, all = TRUE)[order(site, event_start, q)] %>% 
      # Rename columns
      # rename(NO3_rise = NO3, TP_rise = TP_ma9, TDP_rise = TDP_ma9, SRP_rise = SRP_ma9, PP_rise = PP_ma9) %>% 
      rename(turb_rise = turb, NO3_rise = NO3, SRP_rise = SRP_ma9) %>% 
      # Interpolate missing normalized solute values
      group_by(site, event_start) %>% 
      # mutate_at(vars(c(NO3_rise, TP_rise, TDP_rise, SRP_rise, PP_rise)),
      #           .funs = list(~ na.approx(., x = q, xout = q, na.rm = FALSE))) %>% 
      mutate_at(vars(c(turb_rise, NO3_rise, SRP_rise)),
                .funs = list(~ na.approx(., x = q, xout = q, na.rm = FALSE))) %>%       
      # Only keep rows where q matches the q_step above
      filter(q %in% (seq(1,100)/100)) %>% 
      # Take the average of any duplicate values of Q for each site and storm
      # gather(key = "var", value = "val", c(NO3_rise, TP_rise, TDP_rise, SRP_rise, PP_rise)) %>% 
      gather(key = "var", value = "val", c(turb_rise, NO3_rise, SRP_rise)) %>% 
      group_by(site, event_start, event_end, q, var) %>% 
      summarize(val = mean(val, na.rm = T)) %>% 
      spread(var, val) %>% 
      ungroup()
    
  # # Examine individual storm
  # test <- hyst_rise %>%
  #   filter(site == "Wade" & event_start == ymd_hms("2015-10-14 08:30:00", tz = "Etc/GMT-4"))
      
    hyst_fall <- 
      merge(hyst_fall, q_step, all = TRUE)[order(site, event_start, q)] %>% 
      # rename(NO3_fall = NO3, TP_fall = TP_ma9, TDP_fall = TDP_ma9, SRP_fall = SRP_ma9, PP_fall = PP_ma9) %>% 
      rename(turb_fall = turb, NO3_fall = NO3, SRP_fall = SRP_ma9) %>% 
      group_by(site, event_start) %>% 
      # mutate_at(vars(c(NO3_fall, TP_fall, TDP_fall, SRP_fall, PP_fall)),
      #           .funs = list(~ na.approx(., x = q, xout = q, na.rm = FALSE))) %>% 
      mutate_at(vars(c(turb_fall, NO3_fall, SRP_fall)),
                .funs = list(~ na.approx(., x = q, xout = q, na.rm = FALSE))) %>%       
      filter(q %in% (seq(1,100)/100)) %>% 
      # Take the average of any duplicate values of Q for each site and storm
      # gather(key = "var", value = "val", c(NO3_fall, TP_fall, TDP_fall, SRP_fall, PP_fall)) %>% 
      gather(key = "var", value = "val", c(turb_fall, NO3_fall, SRP_fall)) %>% 
      group_by(site, event_start, event_end, q, var) %>% 
      summarize(val = mean(val, na.rm = T)) %>% 
      spread(var, val) %>% 
      ungroup()     
  
  # Note: on 5/30/19 I replaced the replace() line with the mutate() ifelse() line; because the replace line was throwing this error:
  # In x[list] <- values : number of items to replace is not a multiple of replacement length
  # And it's actually just replacing it with the first value in the X_rise vector for that site and storm  
  # With mutate() ifelse() I don't think I need to group_by() anything
  # Join hyst_rise & hyst_fall
  hysteresis <- full_join(hyst_rise, hyst_fall, by = c("site", "event_start", "event_end", "q")) %>% 
    # There were some interpolation errors that made the normalized parameter value at max discharge different for rising and falling limbs;
    # Set them equal
    # replace() solution
    # group_by(site, event_start) %>% 
    # mutate(NO3_fall = replace(NO3_fall, q == 1, NO3_rise),
    #        SRP_fall = replace(SRP_fall, q == 1, SRP_rise),
    #        TDP_fall = replace(TDP_fall, q == 1, TDP_rise),
    #        TP_fall = replace(TP_fall, q == 1, TP_rise))
    # mutate() ifelse() solution
    # mutate(NO3_fall = ifelse(q == 1, NO3_rise, NO3_fall),
    #        SRP_fall = ifelse(q == 1, SRP_rise, SRP_fall),
    #        TDP_fall = ifelse(q == 1, TDP_rise, TDP_fall),
    #        TP_fall = ifelse(q == 1, TP_rise, TP_fall),
    #        PP_fall = ifelse(q == 1, PP_rise, PP_fall))
    mutate(turb_fall = ifelse(q == 1, turb_rise, turb_fall),
           NO3_fall = ifelse(q == 1, NO3_rise, NO3_fall),
           SRP_fall = ifelse(q == 1, SRP_rise, SRP_fall))  
    

  # # Examine individual storm
  # test <- hysteresis %>%
  #   filter(site == "Wade" & event_start >= ymd_hms("2015-10-14 08:30:00", tz = "Etc/GMT-4"))
    
# Calculate HI & FI ----
  # Function to spread multiple value columns at once
  # https://community.rstudio.com/t/spread-with-multiple-value-columns/5378
  spread_n <- function(df, key, value) {
    # quote key
    keyq <- rlang::enquo(key)
    # break value vector into quotes
    valueq <- rlang::enquo(value)
    s <- rlang::quos(!!valueq)
    df %>% gather(variable, value, !!!s) %>%
        unite(temp, !!keyq, variable) %>%
        spread(temp, value)
  }

  # Calculate HI mean, sd, & CV
  HI <- hysteresis %>% 
    # Subtract the normalized concentration on the falling limb from the rising limb for each normalized level of Q
    # mutate(HI_NO3 = NO3_rise - NO3_fall,
    #        HI_SRP = SRP_rise - SRP_fall,
    #        HI_TDP = TDP_rise - TDP_fall,
    #        HI_TP = TP_rise - TP_fall,
    #        HI_PP = PP_rise - PP_fall) %>% 
    mutate(HI_turb = turb_rise - turb_fall,
           HI_NO3 = NO3_rise - NO3_fall,
           HI_SRP = SRP_rise - SRP_fall) %>%     
    # Calculate the mean of HI for each storm and variable
    # gather(key = "var", value = "HI", c(HI_NO3, HI_SRP, HI_TDP, HI_TP, HI_PP)) %>% 
    gather(key = "var", value = "HI", c(HI_turb, HI_NO3, HI_SRP)) %>% 
    group_by(site, event_start, event_end, var) %>% 
    summarize(mean = mean(HI, na.rm = TRUE),
              sd = sd(HI, na.rm = TRUE),
              cv = sd/mean) %>% 
    spread_n(var, c(mean, sd, cv)) %>% 
    ungroup()
    
  # Calculate FI
  FI <- hysteresis %>% 
    # Shed *_fall columns
    select(-c(ends_with("fall"))) %>% 
    # 
    gather(key = "var", value = "conc", c(ends_with("rise"))) %>% 
    group_by(site, event_start, var) %>% 
    # Keep only rows with minimum and maximum Q values (i.e., ~0.01 and 1) which have a concentration value (mostly a concern for minimum value)
    filter(!is.na(conc)) %>%
    filter(q == min(q) | q == max(q)) %>% 
    # Subtract norm. conc. at min. Q from norm. conc. at max. Q
    arrange(q, .by_group = TRUE) %>% 
    mutate(FI = conc - lag(conc, default = first(conc))) %>% 
    # Only keep value at max. Q (this is the FI)
    filter(q == max(q)) %>% 
    # Rearrange the df
    select(-c(q, conc)) %>% 
    spread(var, FI) %>% 
    # rename(FI_NO3 = NO3_rise, FI_SRP = SRP_rise, FI_TDP = TDP_rise, FI_TP = TP_rise, FI_PP = PP_rise) %>% 
    rename(FI_turb = turb_rise, FI_NO3 = NO3_rise, FI_SRP = SRP_rise) %>% 
    ungroup()
  
  # Join HI & FI
  hyst_indices <- full_join(FI, HI, by = c("site", "event_start", "event_end"))
  
    
# Write hyst_indices
  hyst_indices %>% 
    mutate(event_start = as.character(event_start),
           event_end = as.character(event_end)) %>% 
    write_csv("Data/hysteresis_indices.csv")


     

      
# # The following code was an attempt to use Matthew Vaughan's code    
# # Create sensor_data df from alldata for Matt's code below
#   sensor_data <- alldata %>%
#     # Only include event data
#     filter(condition == "event") %>% 
#     # Rename q_cms to q
#     rename(q = q_cms) %>% 
#     # Create unique storm_ID (site initial_eventno)
#     mutate(storm_ID = paste(substr(site, 1, 1), "_", substr(year, 3, 4), "_", eventid, sep = ""))
# 
#   
# # Matthew CH Vaughan
# # 2018-12-07
# # Hysteresis code snippet for Dustin Kincaid and Erin Seybold
# 
# # Calculate the hysteresis index
# # Following Lloyd et al 2016: Testing an improved index for analysing storm discharge-concentration hysteresis
# # Create a standalone function for hysteresis index and related statistics.
# # This generates a list that contains two data frames:
# # [1] contains norm q, associated rising and falling limb norm parameter, and the difference of the two (hysteresis index)
# # [2] contains statistics for that storm, including the mean hysteresis index. 
# hyst_fcn <- function(storm_data, param, interp_step = 0.01) {
#   
#   # Before the real function, lead this with a check for NAs to spit out NA for everything instead of giving an error.
#   if (anyNA(storm_data$q) == TRUE | anyNA(storm_data[ , param]) == TRUE) {
#     hyst <- data.frame(
#       norm_q = NA,
#       rise_norm_param = NA,
#       fall_norm_param = NA,
#       hi = NA,
#       site = storm_data$site[1],
#       storm_ID = storm_data$storm_ID[1],
#       param = param)
#     
#     stats <- data.frame(
#       site = storm_data$site[1],
#       storm_ID = storm_data$storm_ID[1],
#       param = param,
#       mean_hi = NA,
#       flushing_index = NA,
#       coeff_var_hi = NA,
#       portion_hi = NA)
#   } else { # if there aren't NAs, run the real function below. 
#     
#     # Normalize q to set between 0 and 1.
#     storm_data[ , "norm_q"] <- ((storm_data$q - min(storm_data$q)) / (max(storm_data$q) - min(storm_data$q)))
#     
#     # Find row number for peak discharge and number of total rows
#     peak_row <- min(which(storm_data$q == max(storm_data$q))) # min() in case peak q happens for more than one measurement. This takes the first.
#     nrows <- nrow(storm_data)
#     
#     # Calculate the steps that we want to interpolate on. Given in interp_step function input. 
#     steps <- seq(interp_step, 1, by = interp_step)
#     
#     # Some storms have falling q's that don't go back to the same as the beginning. This is the steps we'll be using specifically for the rising and falling limbs.
#     steps_rise <- steps[steps >= min(storm_data[1:peak_row, "norm_q"])]
#     steps_fall <- steps[steps >= min(storm_data[peak_row:nrows, "norm_q"])]
#     
#     # Normalize parameter from 0 to 1
#     storm_data[ , paste("norm", param, sep = "_")] <- ((storm_data[ , param] - min(storm_data[ , param])) / (max(storm_data[ , param]) - min(storm_data[ , param])))
#     
#     # Use linear interpolation to predict normalized parameter at the steps given above - both rising and falling limbs. 
#     # rising limb
#     hyst <- as.data.frame( approx(x = storm_data[1:peak_row, "norm_q"], y = storm_data[1:peak_row, paste("norm", param, sep = "_")], xout = steps_rise) )
#     colnames(hyst) <- c("norm_q", "rise_norm_param") # rename columns
#     # falling limb
#     temp <- as.data.frame( approx(x = storm_data[peak_row:nrows, "norm_q"], y = storm_data[peak_row:nrows, paste("norm", param, sep = "_")], xout = steps_fall) )
#     colnames(temp) <- c("norm_q", "fall_norm_param")
#     
#     # merge the rising and falling dataframes into one
#     hyst <- merge(hyst, temp, by = "norm_q")
#     
#     # There were some interpolation errors that made the normalized parameter value at max discharge different for rising and falling limbs.
#     # Set them equal here with this step.
#     hyst[which(hyst$norm_q == 1), c("rise_norm_param", "fall_norm_param")] <- storm_data[min(which(storm_data$norm_q == 1)), paste("norm", param, sep = "_")]
#     
#     # Calculate the hysteresis index by subtraction
#     hyst[ , "hi"] <- hyst[ , "rise_norm_param"] - hyst[ , "fall_norm_param"]
#     
#     # Add some more info to the data
#     hyst$site <- storm_data$site[1]
#     hyst$storm_ID <- storm_data$storm_ID[1]
#     hyst$param <- param
#     
#     # Make a data frame with the stats of the 
#     stats <- data.frame(
#       site = storm_data$site[1],
#       storm_ID = storm_data$storm_ID[1],
#       param = param,
#       mean_hi = mean(hyst[ , "hi"]),
#       flushing_index = hyst[nrow(hyst), "rise_norm_param"] - hyst[1, "rise_norm_param"],
#       coeff_var_hi = sd(hyst[ , "hi"]) / mean(hyst[ , "hi"]),
#       portion_hi = 1 - min(hyst[ , "norm_q"])
#     )
#     
#   } # close if else bracket
#   
#   result <- list(hyst, stats) # Make a list with both data frames
#   return(result) # return this list.
# } # end function
# 
# 
# # List of params to calculate
# list_params <- c("NO3",
#                  "SRP",
#                  "TDP",
#                  "TP")
# 
# hi_all <- data.frame()
# hi_stats <- data.frame()
# 
# for (i in 1:length(unique(storms$storm_ID))) {
#   ith_storm <- subset(sensor_data, storm_ID == i)
#   for (j in list_params) {
#     
#     output <- hyst_fcn(storm_data = ith_storm, param = j)
#     
#     hi_all <- rbind(hi_all, output[[1]])
#     hi_stats <- rbind(hi_stats, output[[2]])
#   } # end param loop
# } # end storm ID loop  
