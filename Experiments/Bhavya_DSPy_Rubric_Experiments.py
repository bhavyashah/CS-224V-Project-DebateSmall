import os
import json
import csv
import itertools
import datetime
import time
from dataclasses import dataclass
from typing import List, Tuple

import dspy
import fitz
from dotenv import load_dotenv

load_dotenv()

TEAM_MODELS = [
    "gpt-4o-mini",
    "gpt-4.1-mini",
    "gpt-5-mini"
]

JUDGE_MODEL = "gpt-4o"

ROUNDS = 3
OUTPUT_CSV = "debate_results_dspy.csv"
DELAY_BETWEEN_CALLS = 0.25

API_KEY = os.getenv("LITELLM_API_KEY")
API_BASE = os.getenv("LITELLM_API_BASE")

if not API_KEY or not API_BASE:
    raise ValueError("Missing LITELLM_API_KEY or LITELLM_API_BASE in .env file")

@dataclass
class Turn:
    round_index: int
    speaker: str
    text: str
    meta: dict

@dataclass
class DebateResult:
    pairing: Tuple[str, str]
    internet_search: bool
    rounds: int
    turns: List[Turn]
    weighted_total_a: float
    weighted_total_b: float
    explanations: dict
    timestamp: str

def save_results_csv(results: List[DebateResult], path: str):
    fields = [
        "timestamp",
        "pairing",
        "internet_search",
        "rounds",
        "weighted_total_a",
        "weighted_total_b",
        "explanations",
        "turns_full_json"
    ]
    file_exists = os.path.isfile(path)
    
    with open(path, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fields)
        if not file_exists:
            w.writeheader()
        for r in results:
            turns_data = [
                {
                    "round": t.round_index,
                    "speaker": t.speaker,
                    "text": t.text,
                    "meta": t.meta
                }
                for t in r.turns
            ]
            w.writerow({
                "timestamp": r.timestamp,
                "pairing": " vs ".join(r.pairing),
                "internet_search": r.internet_search,
                "rounds": r.rounds,
                "weighted_total_a": r.weighted_total_a,
                "weighted_total_b": r.weighted_total_b,
                "explanations": json.dumps(r.explanations, ensure_ascii=False),
                "turns_full_json": json.dumps(turns_data, ensure_ascii=False),
            })

class RubricExtractionModule(dspy.Module):
    def __init__(self, lm):
        super().__init__()
        self.lm = lm

    def forward(self, handbook_text: str) -> dict:
        prompt = f"""
You are an expert debate adjudication trainer.
Extract a scoring rubric from the following handbook.

--- HANDBOOK ---
{handbook_text}
--- END HANDBOOK ---

Output STRICT JSON:

{{
  "criteria": [
    {{
      "name": "string",
      "weight": float,
      "description": "string"
    }}
  ],
  "scoring_scale": {{
    "0": "label",
    "1": "label",
    "2": "label",
    "3": "label",
    "4": "label",
    "5": "label"
  }}
}}
"""
        with dspy.context(lm=self.lm):
            response = self.lm(prompt)
        
        if isinstance(response, list) and len(response) > 0:
            raw_output = response[0]
        elif hasattr(response, 'choices') and len(response.choices) > 0:
            raw_output = response.choices[0].message.content
        elif hasattr(response, 'content'):
            raw_output = response.content
        elif isinstance(response, dict):
            raw_output = response.get('content', response.get('output', str(response)))
        else:
            raw_output = str(response)
        
        print(f"Raw LM output (first 500 chars): {raw_output[:500]}")
        
        # clean up the output just in case the model added backticks
        clean_json = raw_output.replace("```json", "").replace("```", "").strip()
        return json.loads(clean_json)


class RubricJudgeModule(dspy.Module):
    def __init__(self, lm):
        super().__init__()
        self.lm = lm

    def forward(self, full_a: str, full_b: str, rubric: dict) -> dict:
        rubric_json = json.dumps(rubric, indent=2)

        prompt = f"""
You are a debate judge. Use ONLY the following rubric:

--- RUBRIC ---
{rubric_json}
--- END RUBRIC ---

--- TEAM A FULL TEXT ---
{full_a}
--- TEAM B FULL TEXT ---
{full_b}

Evaluate both teams on every criterion (0–5 scale).
Explain each criterion briefly.
Compute weighted totals.

Output STRICT JSON:

{{
  "team_a": {{"criterion_name": score_int}},
  "team_b": {{"criterion_name": score_int}},
  "weighted_total_a": float,
  "weighted_total_b": float,
  "explanations": {{"criterion_name": "short explanation"}}
}}
"""
        with dspy.context(lm=self.lm):
            response = self.lm(prompt)
        
        if isinstance(response, list) and len(response) > 0:
            raw_output = response[0]
        elif hasattr(response, 'choices') and len(response.choices) > 0:
            raw_output = response.choices[0].message.content
        elif hasattr(response, 'content'):
            raw_output = response.content
        elif isinstance(response, dict):
            raw_output = response.get('content', response.get('output', str(response)))
        else:
            raw_output = str(response)
        
        # clean up the output just in case the model added backticks
        clean_json = raw_output.replace("```json", "").replace("```", "").strip()
        return json.loads(clean_json)


class DebateModel(dspy.Module):
    def __init__(self, model_name: str, lm):
        super().__init__()
        self.model_name = model_name
        self.lm = lm

    def forward(self, prompt, internet_search):
        print(f"DEBUG: calling {self.model_name}...")
        with dspy.context(lm=self.lm, search_enabled=internet_search):
            response = self.lm(prompt)
        
        if isinstance(response, list) and len(response) > 0:
            return response[0]
        elif hasattr(response, 'choices') and len(response.choices) > 0:
            return response.choices[0].message.content
        elif hasattr(response, 'content'):
            return response.content
        elif isinstance(response, dict):
            return response.get('content', response.get('output', str(response)))
        else:
            return str(response)

def run_single_debate(model_a,
                      model_b,
                      judge,
                      rubric,
                      internet_search,
                      rounds,
                      motion):

    turns = []
    last_a, last_b = "", ""
    topic = motion

    for r in range(1, rounds + 1):

        prompt_a = f"Round {r}.\nYou are {model_a.model_name}.\nTopic: {topic}\n"
        if last_b:
            prompt_a += f"Opponent said:\n{last_b}\nRespond directly.\n"
        else:
            prompt_a += "Provide your opening case.\n"

        a_text = model_a(prompt_a, internet_search)

        turns.append(Turn(r, "A", a_text, {"model": model_a.model_name, "search": internet_search}))
        last_a = a_text
        print(f"  Round {r} Team A spoke.")
        time.sleep(DELAY_BETWEEN_CALLS)

        prompt_b = f"Round {r}.\nYou are {model_b.model_name}.\nTopic: {topic}\n"
        prompt_b += f"Opponent said:\n{last_a}\nRespond directly.\n"

        b_text = model_b(prompt_b, internet_search)
        turns.append(Turn(r, "B", b_text, {"model": model_b.model_name, "search": internet_search}))
        last_b = b_text
        print(f"  Round {r} Team B spoke.")
        time.sleep(DELAY_BETWEEN_CALLS)

    full_a = "\n\n".join([t.text for t in turns if t.speaker == "A"])
    full_b = "\n\n".join([t.text for t in turns if t.speaker == "B"])

    print("  Judging debate...")
    judge_out = judge(full_a, full_b, rubric)

    return DebateResult(
        pairing=(model_a.model_name, model_b.model_name),
        internet_search=internet_search,
        rounds=rounds,
        turns=turns,
        weighted_total_a=judge_out["weighted_total_a"],
        weighted_total_b=judge_out["weighted_total_b"],
        explanations=judge_out["explanations"],
        timestamp=datetime.datetime.utcnow().isoformat() + "Z"
    )

def load_pdf_as_text(path):
    try:
        doc = fitz.open(path)
        text = ""
        for page in doc:
            text += page.get_text()
        return text
    except Exception as e:
        print(f"Error loading PDF '{path}': {e}")
        print("Please ensure 'debate_handbook.pdf' is in the same directory.")
        exit(1)

if __name__ == "__main__":
    handbook_path = "debate_handbook.pdf"
    print("=== Loading handbook and extracting rubric ===")
    
    handbook = load_pdf_as_text(handbook_path)
    
    judge_lm = dspy.LM(model=JUDGE_MODEL, api_key=API_KEY, api_base=API_BASE, temperature=0)
    
    team_lms = {}
    for m in TEAM_MODELS:
        if any(x in m.lower() for x in ['o3', 'gpt-5', 'o1']):
            team_lms[m] = dspy.LM(model=m, api_key=API_KEY, api_base=API_BASE, temperature=1.0, max_tokens=16000)
        else:
            team_lms[m] = dspy.LM(model=m, api_key=API_KEY, api_base=API_BASE, temperature=0.7, max_tokens=2000)
    
    extractor = RubricExtractionModule(lm=judge_lm)
    rubric = extractor(handbook)
    print("Rubric extracted successfully.")
    
    judge = RubricJudgeModule(lm=judge_lm)

    model_objs = {m: DebateModel(m, team_lms[m]) for m in TEAM_MODELS}

    # motions to test
    motions = [
        "That this House believes AI copyrights should be abolished.",
        "That we should ban cars in city centers.",
        "That social media does more harm than good."
    ]

    # track scores for each pairing
    pairings_scores = {}
    print("\n=== Running experiments ===")
    
    motion = motions[0]
    search_flag = False
    
    for model in TEAM_MODELS:
        lm = model_objs[model]
        
        print(f"\nRunning debate: {model} (A) vs {model} (B) | Search={search_flag} | Motion: {motion}")
        try:
            res = run_single_debate(
                lm,
                lm,
                judge,
                rubric,
                internet_search=search_flag,
                rounds=ROUNDS,
                motion=motion
            )
            m1_score = res.weighted_total_a
            m2_score = res.weighted_total_b
            
            save_results_csv([res], OUTPUT_CSV)
            
            pairings_scores[(model, model, search_flag)] = (m1_score, m2_score)
            
        except Exception as e:
            print(f"Error in debate execution: {e}")
            import traceback
            traceback.print_exc()

    print(f"\nDone. Results saved to {OUTPUT_CSV}")
    print("Scores Summary:", pairings_scores)