python models/baseline_classification.py \
    "./data/correct_guess_task/train.csv" \
    "./data/correct_guess_task/val.csv" \
    "./data/correct_guess_task/test.csv" \
    "roberta-base-cased" \
    "$1" \
    "output" \
    "/u/nlp/data/codenames_checkpoints/correct_guess_task/roberta_$1_output/"    
