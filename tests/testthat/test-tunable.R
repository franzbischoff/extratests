library(tidymodels)
data("Chicago")

test_that('recipe with no steps', {
  bare_rec <- recipe(ridership ~ ., data = head(Chicago))

  bare_info <- tunable(bare_rec)
  check_tunable_tibble(bare_info)
  expect_equal(nrow(bare_info), 0)
})

test_that('recipe with no tunable parameters', {
  rm_rec <- recipe(ridership ~ ., data = head(Chicago)) %>%
    step_rm(date, ends_with("away"))

  rm_info <- tunable(rm_rec)
  check_tunable_tibble(rm_info)
  expect_equal(nrow(rm_info), 0)
})

test_that('recipe with tunable parameters', {
  spline_rec <- recipe(ridership ~ ., data = head(Chicago)) %>%
    step_date(date) %>%
    step_holiday(date) %>%
    step_rm(date, ends_with("away")) %>%
    step_impute_knn(all_predictors(), neighbors = tune("imputation")) %>%
    step_other(all_nominal(), threshold = tune()) %>%
    step_dummy(all_nominal()) %>%
    step_normalize(all_predictors()) %>%
    step_bs(all_predictors(), deg_free = tune(), degree = tune())

  spline_info <- tunable(spline_rec)
  check_tunable_tibble(spline_info)
  expected_cols <- c('step_impute_knn', 'step_other', 'step_bs', 'step_bs')
  expect_equal(
    spline_info$component,
    expected_cols
  )
  expect_true(all(spline_info$source == "recipe"))
  nms <- c('neighbors', 'threshold', 'deg_free', 'degree')
  expect_equal(spline_info$name, nms)
  expect_true(all(purrr::map_lgl(spline_info$call_info, ~ .x$pkg == "dials")))
  nms <- c('neighbors', 'threshold', 'spline_degree', 'degree_int')
  expect_equal(purrr::map_chr(spline_info$call_info, ~ .x$fun), nms)
})

test_that('model with no parameters', {
  lm_model <- linear_reg() %>% set_engine("lm")

  lm_info <- tunable(lm_model)
  check_tunable_tibble(lm_info)
  expect_equal(nrow(lm_info), 0)
})

test_that('model with main and engine parameters', {
  bst_model <-
    boost_tree(mode = "classification", trees = tune("funky name \n")) %>%
    set_engine("C5.0", rules = tune(), noGlobalPruning = TRUE)

  c5_info <- tunable(bst_model)
  check_tunable_tibble(c5_info)
  expect_equal(nrow(c5_info), 9)
  expect_true(all(c5_info$source == "model_spec"))
  expect_true(all(c5_info$component == "boost_tree"))
  expect_true(all(c5_info$component_id[1:3] == "main"))
  expect_true(all(c5_info$component_id[-(1:3)] == "engine"))
  nms <- c("trees", "min_n", "sample_size", "rules", "CF", "noGlobalPruning",
           "winnow", "fuzzyThreshold", "bands")
  expect_equal(c5_info$name, nms)
  expect_true(all(purrr::map_lgl(c5_info$call_info[1:3], ~ .x$pkg == "dials")))
  expect_equal(
    purrr::map_chr(c5_info$call_info[1:3], ~ .x$fun),
    c("trees", "min_n", "sample_prop")
  )
  expect_true(sum(purrr::map_lgl(c5_info$call_info, is.null)) == 1)
})

test_that('bad model inputs', {
  lm_model <- linear_reg() %>% set_engine("lm")

  bad_class <- lm_model
  class(bad_class) <- c("potato", "model_spec")
  expect_snapshot(
    (expect_error(tunable(bad_class)))
  )
})

test_that("workflow with no tunable parameters", {
  rm_rec <- recipe(ridership ~ ., data = head(Chicago)) %>%
    step_rm(date, ends_with("away"))
  lm_model <- linear_reg() %>% set_engine("lm")
  wf_untunable <- workflow(rm_rec, lm_model)

  wf_info <- tunable(wf_untunable)
  check_tunable_tibble(wf_info)
  expect_equal(nrow(wf_info), 0)
})

test_that("workflow with tunable recipe", {
  spline_rec <- recipe(ridership ~ ., data = head(Chicago)) %>%
    step_date(date) %>%
    step_holiday(date) %>%
    step_rm(date, ends_with("away")) %>%
    step_impute_knn(all_predictors(), neighbors = tune("imputation")) %>%
    step_other(all_nominal(), threshold = tune()) %>%
    step_dummy(all_nominal()) %>%
    step_normalize(all_predictors()) %>%
    step_bs(all_predictors(), deg_free = tune(), degree = tune())
  lm_model <- linear_reg() %>%
    set_engine("lm")
  wf_tunable_recipe <- workflow(spline_rec, lm_model)

  wf_info <- tunable(wf_tunable_recipe)
  check_tunable_tibble(wf_info)
  expect_true(all(wf_info$source == "recipe"))
})

test_that("workflow with tunable model", {
  rm_rec <- recipe(ridership ~ ., data = head(Chicago)) %>%
    step_rm(date, ends_with("away"))
  bst_model <-
    boost_tree(mode = "classification", trees = tune("funky name \n")) %>%
    set_engine("C5.0", rules = tune(), noGlobalPruning = TRUE)
  wf_tunable_model <- workflow(rm_rec, bst_model)

  wf_info <- tunable(wf_tunable_model)
  check_tunable_tibble(wf_info)
  expect_equal(nrow(wf_info), 9)
  expect_true(all(wf_info$source == "model_spec"))
})

test_that("workflow with tunable recipe and model", {
  spline_rec <- recipe(ridership ~ ., data = head(Chicago)) %>%
    step_date(date) %>%
    step_holiday(date) %>%
    step_rm(date, ends_with("away")) %>%
    step_impute_knn(all_predictors(), neighbors = tune("imputation")) %>%
    step_other(all_nominal(), threshold = tune()) %>%
    step_dummy(all_nominal()) %>%
    step_normalize(all_predictors()) %>%
    step_bs(all_predictors(), deg_free = tune(), degree = tune())
  bst_model <-
    boost_tree(mode = "classification", trees = tune("funky name \n")) %>%
    set_engine("C5.0", rules = tune(), noGlobalPruning = TRUE)
  wf_tunable <- workflow(spline_rec, bst_model)

  wf_info <- tunable(wf_tunable)
  check_tunable_tibble(wf_info)
  expect_equal(
    wf_info$source,
    c(rep("model_spec", 9), rep("recipe", 4))
  )
})
