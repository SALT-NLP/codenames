
bash train_gen.sh leaning_only target_selection_task 1 t5-base 15
bash train_gen.sh base_text target_selection_task 1 t5-base 15

bash train_gen_ftext.sh leaning_only clue_generation_task 1 t5-base 20
bash train_gen_ftext.sh base_text clue_generation_task 1 t5-base 20

bash train_gen.sh event_only generate_guess_task 1 t5-base 25
bash train_gen.sh base_text generate_guess_task 1 t5-base 25

bash train_gen.sh leaning_only guess_rationale_task 1 t5-base 15
bash train_gen.sh base_text guess_rationale_task 1 t5-base 15

bash train_gen.sh all_text target_rationale_task 1 t5-base 15
bash train_gen.sh base_text target_rationale_task 1 t5-base 15

bash train_classification.sh personality_only
bash train_classification.sh base_text
