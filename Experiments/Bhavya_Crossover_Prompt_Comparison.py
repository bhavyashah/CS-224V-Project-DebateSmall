import dspy
from dataclasses import dataclass
from typing import List
import os
from dotenv import load_dotenv
import pandas as pd
import argparse

load_dotenv()

# enhanced prompts have more detailed structure requirements
ENHANCED_PROMPTS = {
    "prop_1": """You are the First Proposition speaker in a 3v3 debate. Your goal is to set up the debate and provide the core constructive arguments for your side. The speech must be approximately 1200 to 1300 words long to simulate an 8-minute speech at a slightly above-average speaking rate. Do not use formalities, greetings, or restate the motion at the start. Dive immediately into the content.

Structure your speech as follows:

1. Introduction (approx. 100 words): Start with a strong, punchy opening that captures the main philosophical or practical point of your side.
2. Model and Definitions (approx. 150 words): Define the motion clearly. Explain what the world looks like under your proposal and, crucially, what it does not look like to avoid ambiguity. If the motion is normative, define the burden of proof.
3. Arguments (approx. 1000 words): Present 2 or 3 distinct but thematically related arguments.
    - Structure: For each argument, strictly follow a structural logic flow starting with a Premise.
    - Mechanisms: Provide multiple mechanisms for each argument. Do not rely on a single reason; layer your logic with several steps explaining why the outcome happens.
    - Impacts: Provide multiple impacts for each argument. Explain the various consequences (moral, practical, emotional) and why they matter.
    - Evidence: Use examples to illustrate logic, but prioritize structural reasoning over obscure statistics.
4. Conclusion (approx. 50 words): A very short summarization of the key pointers.""",

    "opp_1": """You are the First Opposition speaker in a 3v3 debate. Your goal is to rebut the Proposition's setup and present your team's constructive case. The speech must be approximately 1200 to 1300 words long. Do not use formalities or greetings.

Structure your speech as follows:

1. Introduction (approx. 100 words): Start with a punchy capture of why the Proposition is wrong or dangerous.
2. Counter-Model (approx. 100 words): Briefly explain your stance. Are you defending the status quo, or proposing a specific counter-alternative? Keep this concise.
3. Rebuttal (approx. 300 words): Spend about 2 minutes dismantling the biggest claims made by First Proposition. Focus on strategic flaws in their logic.
4. Arguments (approx. 750 words): Spend the majority of your time (about 5 minutes) on 2 significant constructive arguments against the motion.
    - Structure: Use a strict Premise-Mechanism-Impact structure.
    - Depth: Include multiple mechanisms to prove why your claims are true and multiple impacts to show the breadth of the consequences.
5. Conclusion (approx. 50 words): Briefly summarize why the Opposition case stands.""",

    "prop_2": """You are the Second Proposition speaker in a 3v3 debate. Your goal is to defend your team's case, rebut the Opposition, and add a new extension. The speech must be approximately 1200 to 1300 words long. Do not use formalities or greetings.""",

    "opp_2": """You are the Second Opposition speaker in a 3v3 debate. Your goal is to destroy the Proposition's case, rebuild your own, and add a new dimension to the debate. The speech must be approximately 1200 to 1300 words long. Do not use formalities or greetings.""",

    "prop_3": """You are the Third Proposition speaker (Prop Whip). Your goal is to summarize the debate and prove why your team has won. The speech must be approximately 1200 to 1300 words long. Do not use formalities or greetings.""",

    "opp_3": """You are the Third Opposition speaker (Opp Whip). Your goal is to close the debate and prove why the Opposition has won. The speech must be approximately 1200 to 1300 words long. Do not use formalities or greetings."""
}

# baseline prompts are simpler, less structured
BASELINE_PROMPTS = {
    "prop_1": "You are the First Proposition speaker in a 3v3 debate. Your speech should be approximately 1200 words. Do not use greetings or pleasantries. Please define the motion and present the main constructive arguments for the Proposition side.",
    
    "opp_1": "You are the First Opposition speaker in a 3v3 debate. Your speech should be approximately 1200 words. Do not use greetings or pleasantries. Please rebut the First Proposition speaker and present the main constructive arguments for the Opposition side.",

    "prop_2": "You are the Second Proposition speaker in a 3v3 debate. Your speech should be approximately 1200 words. Do not use greetings or pleasantries. Please rebut the Opposition, defend your partner's arguments, and introduce a new constructive argument.",
    
    "opp_2": "You are the Second Opposition speaker in a 3v3 debate. Your speech should be approximately 1200 words. Do not use greetings or pleasantries. Please rebut the Proposition, defend your partner's arguments, and introduce a new constructive argument.",

    "prop_3": "You are the Third Proposition speaker in a 3v3 debate. Your speech should be approximately 1200 words. Do not use greetings or pleasantries. Please summarize the debate and explain why the Proposition team has won. Do not introduce new constructive arguments.",
    
    "opp_3": "You are the Third Opposition speaker in a 3v3 debate. Your speech should be approximately 1200 words. Do not use greetings or pleasantries. Please summarize the debate and explain why the Opposition team has won. Do not introduce new constructive arguments."
}


@dataclass
class Turn:
    speaker_position: str
    team: str
    speaker_number: int
    speech: str
    architecture: str

@dataclass
class DebateResult:
    motion: str
    prop_model: str
    opp_model: str
    judge_model: str
    prop_architecture: str
    opp_architecture: str
    turns: List[Turn]
    prop_scores: List[int]
    opp_scores: List[int]
    winner: str
    reason_for_decision: str


class DebateSpeaker:
    
    def __init__(self, lm, speaker_position, architecture):
        self.lm = lm
        self.speaker_position = speaker_position
        self.architecture = architecture
        
        if architecture == "enhanced":
            self.prompt = ENHANCED_PROMPTS[speaker_position]
        else:
            self.prompt = BASELINE_PROMPTS[speaker_position]
    
    def generate_speech(self, motion, previous_speeches):
        context = f"Motion: {motion}\n\n"
        
        if previous_speeches:
            context += "Previous speeches:\n"
            for i, speech in enumerate(previous_speeches, 1):
                context += f"\nSpeech {i}:\n{speech}\n"
        
        context += f"\n{self.prompt}\n\nYour speech:"
        
        print(f"DEBUG: generating speech for {self.speaker_position}...")
        with dspy.context(lm=self.lm):
            response = self.lm(prompt=context)
            if isinstance(response, list):
                result = response[0] if response else ""
            else:
                result = response
            print(f"DEBUG: generated {len(result.split())} words")
            return result

def judge_debate(motion, turns, judge_lm):
    transcript = f"Motion: {motion}\n\n"
    for turn in turns:
        transcript += f"\n--- {turn.team} Speaker {turn.speaker_number} ---\n{turn.speech}\n"
    
    # wudc-style judging prompt
    judge_prompt = f"""You are an Expert Debate Adjudicator

You are tasked with judging a 3v3 debate between Proposition and Opposition teams. You must adopt the persona of the Ordinary Intelligent Voter (OIV) as defined by the WUDC Debating Manual.

Your Persona & Disposition
- Knowledge Base: You are a smart, generalist reader. You know basic geopolitical and social facts (e.g., you know Syria is in the Middle East), but you do not possess specialist or technical knowledge (e.g., you do not know specific legal precedents or complex economic formulas).
- Open-Mindedness: You have no preformed views on the topic. You are cynical about mere assertions and require reasoned analysis to be persuaded.
- Neutrality: You must not judge based on your personal preferences or political alignment. You judge solely on the persuasiveness of the arguments presented within the text.

Your Evaluation Process
You must evaluate the debate based on four weighted axes.

1. Argumentation & Analysis (45%)
- Logic over Assertion: Do not credit bare assertions. Credit arguments that provide mechanistic links - reasons why X leads to Y.
- Impact: Credit teams that explain why an outcome matters (morally, practically, or emotionally).
- Consistency: Check for contradictions. If a later speaker contradicts an earlier partner, ignore the later claim and stick to the team's original stance.
- Plausibility: Reject claims that are factually absurd or logical leaps that an ordinary person would find impossible to believe.

2. Engagement & Rebuttal (35%)
- Direct Responsiveness: You must track which arguments were answered. If a team ignores a core argument from their opponents, you must treat that argument as conceded and true.
- The Silence Rule: If Proposition proves X is true and Opposition never mentions X, then X is a fact in this debate. You must weigh this fact in your final decision.
- Comparative Weighing: Give higher credit to teams that explicitly compare their impacts against their opponents' (e.g., Our impact affects fewer people but is a breach of a more important human right).

3. Role Fulfillment (10%)
- 1st Proposition: Must define the motion. If the definition is a squirrel (unfairly restrictive or logically impossible), penalize them heavily.
- 1st Opposition: Must oppose the motion. They may defend the status quo or propose a counter-model.

4. Clarity of Expression (10%)
- Precision: Evaluate whether the meaning of the text is unambiguous.
- Comprehensibility: The text must be clear enough for an average reader to follow the logic.
- Note on Jargon: While you should not penalize the use of technical terms heavily, if a term renders an argument confusing to a layperson, treat the argument as less persuasive.

Scoring Guide (Strict Adherence Required)

You must assign a score between 50 and 100 to each speech. Be extremely strict. Do not succumb to grade inflation.

- 90-100 (Legendary/Rare): Do not award this lightly. This score is reserved for the best speeches in human history. The argument is flawless, the rebuttal is devastating, and it is nearly impossible to imagine a better speech.
- 85-89 (Exceptional): A very high bar. The speech addresses the core issues with sophisticated analysis and has almost no flaws.
- 80-84 (Very Good): A high-quality speech. It is relevant, deeply analytical, and well-structured, but may have minor vulnerabilities.
- 75-79 (Good/Competent): Relevant and logical, but may rely on some simplifications or miss minor nuances.
- 70-74 (Beginner/Average): The speech is relevant but has significant logical gaps or relies on assertions rather than proof.
- 60-69 (Below Average/Poor): Hard to follow, barely relevant, or logically confused.
- 50-59 (Non-Functional): Irrelevant content or gibberish.

Step-by-Step Decision Protocol

1. Identify Claims: List the core arguments made by Proposition and Opposition.
2. Filter Invalid Arguments:
- Delete arguments based on knifing (contradicting partners).
- Delete assertions that lack logical backing.
3. Determine Truth:
- Did the Opponent rebut Claim A?
- If YES: Evaluate who had better analysis.
- If NO: Claim A is true.
4. Weigh Impacts: Compare the surviving impacts. Use the metrics provided by the teams. If no metrics were provided, use your common sense as an Ordinary Intelligent Voter.
5. Score Each Speaker: Assign a score between 50-100 to each speaker based on the criteria above.
6. Calculate Total Scores: Sum all speaker scores for each team.
7. Declare Winner: THE TEAM WITH THE HIGHER TOTAL SCORE WINS. This is a mathematical determination based on the scores you assigned. If Proposition's total score is higher, Proposition wins. If Opposition's total score is higher, Opposition wins. You must follow this rule strictly.

--- DEBATE TRANSCRIPT ---
{transcript}
--- END TRANSCRIPT ---

Provide your evaluation in this EXACT format:

PROPOSITION SPEAKER 1 SCORE: [score]
OPPOSITION SPEAKER 1 SCORE: [score]
PROPOSITION SPEAKER 2 SCORE: [score]
OPPOSITION SPEAKER 2 SCORE: [score]
PROPOSITION SPEAKER 3 SCORE: [score]
OPPOSITION SPEAKER 3 SCORE: [score]
WINNER: [Proposition/Opposition]
REASON: [Your detailed RFD explaining why this team won]
"""
    
    with dspy.context(lm=judge_lm):
        response = judge_lm(prompt=judge_prompt)
    
    if isinstance(response, list):
        response = response[0] if response else ""
    
    lines = response.strip().split('\n')
    
    # parse the scores from llm response
    p_scores_map = {1: None, 2: None, 3: None}
    o_scores_map = {1: None, 2: None, 3: None}
    
    reason_lines = []
    capturing_reason = False
    
    for line in lines:
        lower_line = line.lower()
        if "proposition speaker" in lower_line and "score:" in lower_line:
            try:
                parts = lower_line.split("proposition speaker")[1].split("score:")
                speaker_num = int(parts[0].strip())
                score = int(parts[1].strip().split()[0])
                if speaker_num in p_scores_map:
                    p_scores_map[speaker_num] = score
            except:
                pass
        elif "opposition speaker" in lower_line and "score:" in lower_line:
            try:
                parts = lower_line.split("opposition speaker")[1].split("score:")
                speaker_num = int(parts[0].strip())
                score = int(parts[1].strip().split()[0])
                if speaker_num in o_scores_map:
                    o_scores_map[speaker_num] = score
            except:
                pass
        elif line.startswith("REASON:"):
            reason_lines.append(line.split("REASON:")[1].strip())
            capturing_reason = True
        elif capturing_reason and line.strip() and not line.upper().startswith("WINNER"):
            reason_lines.append(line.strip())
    
    prop_scores = [p_scores_map[i] for i in range(1, 4) if p_scores_map[i] is not None]
    opp_scores = [o_scores_map[i] for i in range(1, 4) if o_scores_map[i] is not None]
    
    # winner is whoever has higher total
    p_total = sum(prop_scores) if prop_scores else 0
    o_total = sum(opp_scores) if opp_scores else 0
    
    if p_total > o_total:
        winner = "Proposition"
    elif o_total > p_total:
        winner = "Opposition"
    else:
        winner = "Tie"
    
    reason = " ".join(reason_lines) if reason_lines else ""
    
    return prop_scores, opp_scores, winner, reason


def run_crossover_debate(motion, 
                        prop_architecture,
                        opp_architecture,
                        prop_model_name, 
                        opp_model_name,
                        judge_model_name,
                        prop_lm, 
                        opp_lm, 
                        judge_lm,
                        num_turns=3):
    
    print(f"\n=== Running Crossover Debate ({num_turns}v{num_turns}) ===")
    print(f"Motion: {motion}")
    print(f"Proposition: {prop_model_name} ({prop_architecture} architecture)")
    print(f"Opposition: {opp_model_name} ({opp_architecture} architecture)")
    print(f"Judge: {judge_model_name}\n")
    
    turns = []
    previous_speeches = []
    
    # speaking order for bp style debate
    full_speaking_order = [
        ("prop_1", "Proposition", 1),
        ("opp_1", "Opposition", 1),
        ("prop_2", "Proposition", 2),
        ("opp_2", "Opposition", 2),
        ("prop_3", "Proposition", 3),
        ("opp_3", "Opposition", 3)
    ]
    
    speaking_order = full_speaking_order[:num_turns * 2]
    
    for position, team, speaker_num in speaking_order:
        arch = prop_architecture if team == "Proposition" else opp_architecture
        lm = prop_lm if team == "Proposition" else opp_lm
        
        speaker = DebateSpeaker(lm, position, arch)
        
        print(f"  {team} Speaker {speaker_num} generating speech...")
        speech = speaker.generate_speech(motion, previous_speeches)
        turns.append(Turn(position, team, speaker_num, speech, arch))
        previous_speeches.append(speech)
        print(f"  {team} Speaker {speaker_num} spoke.")
    
    print("\n  Judging debate...")
    prop_scores, opp_scores, winner, rfd = judge_debate(motion, turns, judge_lm)
    print(f"  Winner: {winner}\n")
    
    return DebateResult(
        motion=motion,
        prop_model=prop_model_name,
        opp_model=opp_model_name,
        judge_model=judge_model_name,
        prop_architecture=prop_architecture,
        opp_architecture=opp_architecture,
        turns=turns,
        prop_scores=prop_scores,
        opp_scores=opp_scores,
        winner=winner,
        reason_for_decision=rfd
    )

def main():
    parser = argparse.ArgumentParser(
        description='Run crossover debate with configurable models and architectures',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python crossover_debate.py -t 3 -pm 4o -om 4o-mini -pa enhanced -oa baseline
  python crossover_debate.py -t 1 -pm o1-mini -om o1-mini -pa enhanced -oa baseline
  python crossover_debate.py -t 2 -pm 4o-mini -om 4o-mini -pa baseline -oa enhanced
        """
    )
    
    parser.add_argument('-t', '--turns', type=int, choices=[1, 2, 3], default=3,
                        help='Number of turns (1, 2, or 3)')
    parser.add_argument('-pm', '--prop-model', type=str, default='4o-mini',
                        choices=['4o', '4o-mini', 'o1', 'o1-mini'],
                        help='Model for Proposition')
    parser.add_argument('-om', '--opp-model', type=str, default='4o-mini',
                        choices=['4o', '4o-mini', 'o1', 'o1-mini'],
                        help='Model for Opposition')
    parser.add_argument('-pa', '--prop-arch', type=str, default='baseline',
                        choices=['enhanced', 'baseline'],
                        help='Architecture for Proposition')
    parser.add_argument('-oa', '--opp-arch', type=str, default='enhanced',
                        choices=['enhanced', 'baseline'],
                        help='Architecture for Opposition')
    parser.add_argument('-jm', '--judge-model', type=str, default='o3',
                        choices=['o3', 'o1'],
                        help='Judge model')
    parser.add_argument('-m', '--motion', type=str, default='This house would make voting mandatory',
                        help='Debate motion')
    parser.add_argument('-o', '--output', type=str, default='crossover_debate_results.csv',
                        help='Output CSV filename')
    
    args = parser.parse_args()
    
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("OPENAI_API_KEY not found in environment")
    
    print("=== Initializing models ===")
    print("Using OpenAI API directly")
    
    # map short names to full openai model names
    model_map = {
        '4o': 'gpt-4o',
        '4o-mini': 'gpt-4o-mini',
        'o1': 'o1',
        'o1-mini': 'o1-mini'
    }
    
    prop_model_full = model_map.get(args.prop_model, args.prop_model)
    opp_model_full = model_map.get(args.opp_model, args.opp_model)
    judge_model_full = model_map.get(args.judge_model, args.judge_model)
    
    prop_lm = dspy.LM(f'openai/{prop_model_full}', api_key=api_key)
    opp_lm = dspy.LM(f'openai/{opp_model_full}', api_key=api_key)
    judge_lm = dspy.LM(f'openai/{judge_model_full}', api_key=api_key)
    
    print("\n" + "="*80)
    print(f"MATCHUP: {args.prop_arch.title()} Prop ({args.prop_model}) vs {args.opp_arch.title()} Opp ({args.opp_model})")
    print("="*80)
    
    result = run_crossover_debate(
        motion=args.motion,
        prop_architecture=args.prop_arch,
        opp_architecture=args.opp_arch,
        prop_model_name=prop_model_full,
        opp_model_name=opp_model_full,
        judge_model_name=judge_model_full,
        prop_lm=prop_lm,
        opp_lm=opp_lm,
        judge_lm=judge_lm,
        num_turns=args.turns
    )
    
    print(f"\n=== Crossover Debate Complete ===")
    print(f"Winner: {result.winner}")
    print(f"Proposition Total: {sum(result.prop_scores)}")
    print(f"Opposition Total: {sum(result.opp_scores)}")
    
    # build output dict
    data = {
        "motion": [args.motion],
        "num_turns": [args.turns],
        "prop_model": [prop_model_full],
        "opp_model": [opp_model_full],
        "judge_model": [judge_model_full],
        "prop_architecture": [result.prop_architecture],
        "opp_architecture": [result.opp_architecture],
        "winner": [result.winner],
        "reason_for_decision": [result.reason_for_decision],
        "prop_total_score": [sum(result.prop_scores)],
        "opp_total_score": [sum(result.opp_scores)],
    }
    
    for i in range(3):
        data[f"prop_{i+1}_score"] = [result.prop_scores[i] if i < len(result.prop_scores) else None]
        data[f"opp_{i+1}_score"] = [result.opp_scores[i] if i < len(result.opp_scores) else None]
    
    for speaker_num in range(1, 4):
        data[f"prop_{speaker_num}_speech"] = [None]
        data[f"opp_{speaker_num}_speech"] = [None]
    
    for turn in result.turns:
        team_prefix = "prop" if turn.team.lower() == "proposition" else "opp"
        key = f"{team_prefix}_{turn.speaker_number}_speech"
        data[key] = [turn.speech]
    
    df = pd.DataFrame(data)
    
    # append or create csv
    if os.path.exists(args.output):
        existing_df = pd.read_csv(args.output)
        df = pd.concat([existing_df, df], ignore_index=True)
    
    df.to_csv(args.output, index=False)
    print(f"\nResults saved to {args.output}")
    
    print("\n" + "="*80)
    print("FULL TRANSCRIPT")
    print("="*80)
    for turn in result.turns:
        print(f"\n--- {turn.team} Speaker {turn.speaker_number} ({turn.architecture}) ---")
        print(turn.speech)

if __name__ == "__main__":
    main()
