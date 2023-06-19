# bash train_gen.sh col task iter model epochs
# bash train_gen.sh 1   2    3    4     5

# bash train_gen.sh base_text target_rationale_task 1 t5-base

python models/baseline_summarization_wvec.py \
    --train_file="./data/$2/train.csv" \
    --text_column="$1" \
    --summary_column="output" \
    --validation_file="./data/$2/val.csv" \
    --test_file="./data/$2/test.csv" \
    --output_dir="/u/nlp/data/codenames_checkpoints/$2/$4_$1_$3_output/" \
    --model_name_or_path="$4" \
    --predict_with_generate \
    --num_train_epochs $5 \
    --do_train --do_eval --do_predict --overwrite_output_dir \
    --use_fasttext \
    --metric_for_best_model "bertscore" \
    --save_strategy "epoch" \
    --save_total_limit 1 \
    --load_best_model_at_end \
    --logging_strategy "epoch" \
    --evaluation_strategy "epoch"
