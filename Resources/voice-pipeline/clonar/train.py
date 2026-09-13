#!/usr/bin/env python3
"""Fine-tune GPT de XTTS con base y dataset gestionados por BtoDicta."""
import math, os, sys, warnings
warnings.filterwarnings("ignore")
os.environ["COQUI_TOS_AGREED"] = "1"; os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
from trainer import Trainer, TrainerArgs
from TTS.config.shared_configs import BaseDatasetConfig
from TTS.tts.datasets import load_tts_samples
from TTS.tts.layers.xtts.trainer.gpt_trainer import GPTArgs, GPTTrainer, GPTTrainerConfig
from TTS.tts.models.xtts import XttsAudioConfig
GPTTrainer.train_log = lambda self, *a, **k: None
GPTTrainer.eval_log = lambda self, *a, **k: None

def main():
    project = sys.argv[1]; steps = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    pipeline = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(pipeline, "xtts_base")
    dataset = os.path.join(project, "dataset"); out = os.path.join(project, "run")
    os.makedirs(out, exist_ok=True)
    ds = BaseDatasetConfig(formatter="coqui", dataset_name="voz", path=dataset,
        meta_file_train="metadata_train.csv", meta_file_val="metadata_eval.csv", language="es")
    args = GPTArgs(max_conditioning_length=132300, min_conditioning_length=66150,
        max_wav_length=330750, max_text_length=200,
        mel_norm_file=os.path.join(base, "mel_stats.pth"),
        dvae_checkpoint=os.path.join(base, "dvae.pth"),
        xtts_checkpoint=os.path.join(base, "model.pth"),
        tokenizer_file=os.path.join(base, "vocab.json"),
        gpt_num_audio_tokens=1026, gpt_start_audio_token=1024, gpt_stop_audio_token=1025,
        gpt_use_masking_gt_prompt_approach=True, gpt_use_perceiver_resampler=True)
    audio = XttsAudioConfig(sample_rate=22050, dvae_sample_rate=22050, output_sample_rate=24000)
    train, evaluation = load_tts_samples([ds], eval_split=True, eval_split_max_size=128,
                                         eval_split_size=0.02)
    batches = max(1, len(train) // 3)
    if steps <= 0: steps = min(5000, max(600, batches * 12))
    epochs = max(2, math.ceil(steps / batches))
    candidates = [50,100,150,200,250,300,400,500,750,1000,1500,2000]
    save = min(candidates, key=lambda n: abs(n - steps / 10)); keep = 12
    cfg = GPTTrainerConfig(epochs=epochs, output_path=out, model_args=args, audio=audio,
        run_name="voz", project_name="btodicta", batch_size=3, batch_group_size=32,
        eval_batch_size=3, num_loader_workers=0, eval_split_max_size=128,
        print_step=50, save_step=save, save_n_checkpoints=keep,
        save_checkpoints=True, print_eval=False, optimizer="AdamW",
        optimizer_wd_only_on_weights=True,
        optimizer_params={"betas":[0.9,0.96],"eps":1e-8,"weight_decay":1e-2},
        lr=5e-06, lr_scheduler="MultiStepLR",
        lr_scheduler_params={"milestones":[2000,5000,9000],"gamma":0.5,"last_epoch":-1},
        test_sentences=[])
    model = GPTTrainer.init_from_config(cfg)
    print(f"[i] train={len(train)} eval={len(evaluation)} epochs={epochs} (~{steps} pasos)", flush=True)
    count = min(keep, steps // save)
    print(f"[PLAN] {epochs} pasadas sobre {len(train)} clips = ~{steps} pasos", flush=True)
    print(f"[DISCO] guarda cada {save} pasos, máx {keep} checkpoints (~{count})", flush=True)
    Trainer(TrainerArgs(restore_path=None, skip_train_epoch=False, start_with_eval=False,
            grad_accum_steps=4), cfg, output_path=out, model=model,
            train_samples=train, eval_samples=evaluation).fit()

if __name__ == "__main__": main()
