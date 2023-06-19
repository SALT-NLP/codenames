
import os
import json

checkpoint_dir = "/u/nlp/data/codenames_checkpoints/"
selected_metrics = [
    "eval_validation_rouge1", 
    "eval_validation_rouge2", 
    "eval_validation_rougeLsum", 
    "eval_validation_bleu", 
    "eval_validation_bertscore", 
    "eval_validation_gen_len"
]
tasks = [
    "generate_guess_task",
    "target_selection_task",
    "clue_generation_task"
]
best_metric = "eval_validation_rougeLsum"

test_scores = {}
for task in tasks:
    print(task)
    for model in sorted(os.listdir(checkpoint_dir + task)):
        train_state_json = checkpoint_dir + task + "/" + model + "/trainer_state.json"
        agg_key = "_".join(model.split("_")[:-2])
        try:
            with open(train_state_json) as f:
                print(train_state_json)
                d = json.load(f)
                all_epochs = []
                for metric in [best_metric]:
                    max_score = max(d["log_history"], key=lambda x: x[metric] if metric in x else -999)
                    if metric in max_score:
                        max_epoch = max_score["epoch"]
                        all_epochs.append(max_epoch)
                best_min_epoch = min(all_epochs)
                print(best_min_epoch)
                for metric in selected_metrics:
                    if "validation" in metric:
                        test_metric = metric.replace("validation", "test")
                        rem = [x for x in d["log_history"] if test_metric in x and x["epoch"] == best_min_epoch]
                        if agg_key not in test_scores: test_scores[agg_key] = {}
                        if test_metric not in test_scores[agg_key]: test_scores[agg_key][test_metric] = []
                        test_scores[agg_key][test_metric].append(rem[0][test_metric])
                        print(test_metric + " " + str(rem[0][test_metric]))
        except:
            print(train_state_json)
            print("failed")
        print()
