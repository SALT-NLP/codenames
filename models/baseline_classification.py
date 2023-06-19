import transformers
import numpy as np
from transformers import AutoTokenizer, AutoModelForSequenceClassification, TrainingArguments, Trainer
import sys
from datasets import load_dataset, load_metric

n = len(sys.argv)
print("Total arguments passed:", n)

for i in range(1, n):
    print(sys.argv[i])

model_checkpoint = sys.argv[4]
batch_size = 32


data_files = {
    "train": sys.argv[1], 
    "validation": sys.argv[2],
    "test": sys.argv[3]
}

dataset = load_dataset(
    "csv",
    data_files=data_files
)

metric = load_metric('f1')
curr_cols = [k for k in dataset["train"][0]]
dataset = dataset.remove_columns([col for col in curr_cols if col not in [sys.argv[5], sys.argv[6]]])

    
tokenizer = AutoTokenizer.from_pretrained(model_checkpoint, use_fast=True)

num_labels = 2
model = AutoModelForSequenceClassification.from_pretrained(model_checkpoint, num_labels=num_labels)

model_name = model_checkpoint.split("/")[-1]

args = TrainingArguments(
    sys.argv[7],
    learning_rate=5e-6,
    per_device_train_batch_size=batch_size,
    per_device_eval_batch_size=batch_size,
    num_train_epochs=25,
    # weight_decay=0.01,
    metric_for_best_model="f1",
    # save_strategy="no",
    save_strategy="epoch",
    save_total_limit = 1, # Only last 2 models are saved. Older ones are deleted.
    load_best_model_at_end=True,
    logging_strategy="epoch",
    evaluation_strategy = "epoch",
    dataloader_drop_last=True
)


def preprocess_function(examples):
    result = tokenizer(examples[sys.argv[5]], truncation=True)
    result["label"] = [1 if l else 0 for l in examples[sys.argv[6]]]
    return result

encoded_dataset = dataset.map(preprocess_function, batched=True)

def compute_metrics(eval_pred):
    predictions, labels = eval_pred
    predictions = np.argmax(predictions, axis=1)
    ret = metric.compute(predictions=predictions, references=labels, average="macro")
    return ret

validation_key = "validation"
trainer = Trainer(
    model,
    args,
    train_dataset=encoded_dataset["train"],
    eval_dataset={  "validation": encoded_dataset[validation_key], "test": encoded_dataset["test"] },
    tokenizer=tokenizer,
    compute_metrics=compute_metrics    
)

trainer.train()
