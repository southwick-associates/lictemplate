# function(s) to be called from 1-run-history.R

# Run license history by permission (group)
# 
# This function encapsulates the workflow for producing license history for 
# a specified permission. It is included in template code (rather than in sadash)
# because state-specific tweaking of the workflow may be necessary.
# 
# - group: name of group to output to db_history
# - yrs_group: year range to include in make_history()
# - lic_filter: lic table filter condition for selecting permission sales
# - group_parent: name of parent group (for subtype permissions, otherwise NULL)
# - rank_var: passed to rank_sale()
# - carry_vars: passed to make_history()
run_group <- function(
    group, lic_filter, yrs_group = yrs, group_parent = NULL, 
    rank_var = c("duration", "res"), carry_vars = c("month", "res")
) {
    # lapse should only be computed for full years
    yrs_lapse <- if (quarter == 4) yrs_group else yrs_group[-length(yrs_group)]
    
    lic_group <- all$lic %>%
        filter_(lic_filter)
    
    history <- lic_group  %>%
        select(lic_id, duration) %>%
        inner_join(all$sale, by = "lic_id") %>%
        drop_na_custid() %>%
        rank_sale(rank_var, first_month = TRUE) %>%
        make_history(yrs_group, carry_vars, yrs_lapse)
    
    if (!is.null(group_parent)) {
        # subtypes: use parent group for R3 & lapse
        history_parent <- db_history %>%
            load_history(group_parent, yrs_group) %>%
            select(cust_id, year, lapse, R3)
        history <- history %>%
            select(-R3, -lapse) %>%
            left_join(history_parent, by = c("cust_id", "year"))
    }
    write_history(history, group, lic_group, db_history, db_license)
}
