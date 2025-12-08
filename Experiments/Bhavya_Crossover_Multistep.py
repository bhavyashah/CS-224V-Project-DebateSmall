import dspy
from dataclasses import dataclass
from typing import List, Optional
import os
from dotenv import load_dotenv
import pandas as pd
import argparse

load_dotenv()

# prompts for the multi-phase argument generation
ARG_GEN_PROMPT = """You are a divergent debate engine designed to build a constructive case.

Phase 1: Brainstorming (Divergence)
Generate 20 distinct argument fragments for your side. Each fragment must have:
  - Premise: The starting condition.
  - Mechanism: The specific causal chain (How A leads to B).
  - Impact: The final outcome.
  - Constraint: The MECHANISM must be unique for every fragment. You may have similar impacts, but the logical path to get there must be different.

Phase 2: Filtering (Contextual - 2nd Speakers Only)
  - If you are Prop 2 or Opp 2: Read your teammate's previous speech.
  - DELETE any of your 20 fragments where the mechanism was already explained by your teammate. We need extensions, not repetition.

Phase 3: Ranking (Strategic)
  - Evaluate the remaining fragments. Rank them from 1 to N based on logical strength and strategic value.

Phase 4: Clustering (Convergence)
Group the top-ranked fragments into thematic arguments based on your role:
  - If 1st Speaker (Prop 1 / Opp 1): Take the top 6-10 fragments and cluster them into 2 distinct Contentions.
  - If 2nd Speaker (Prop 2 / Opp 2): Take the top 3-5 fragments and cluster them into 1 single Extension Argument.

Output: Return only the final clustered arguments with their taglines.
"""

EXTRACT_PROMPT = """You are an expert debate adjudicator and strategist. Your goal is to map the opponent's case into a structured hierarchy of threats.

Step 1: Atomic Extraction
Analyze the transcript(s). Extract distinct 'Strategic Ideas'. A Strategic Idea must be one of:
  - Mechanism Flaw: Why their action fails, won't happen, or won't lead to the result.
  - Impact Claim: Why their outcome matters (or explaining why it doesn't).
  - Characterization: How they define the world or the status quo.
  Constraint: Extract ONLY from the opponent's speech provided.

Step 2: Strategic Ranking
Rank these atomic ideas from 1 to N based on 'Damage Potential' - which points are most likely to lose us the debate if left unanswered?

Step 3: Thematic Clustering
Group the top-ranked ideas into {NUM_BUCKETS} thematic buckets.
  - If 2nd Speaker: Create 2 Buckets.
  - If 3rd Speaker: Create 3 Buckets.

Output Format:
Return a structured object:
  - Bucket 1 (Theme Name):
      - Idea 1: [Description of Mechanism/Impact] (Rank: High)
      - Idea 2: [Description] (Rank: Medium)
  - Bucket 2 (Theme Name): ...
"""

REFUTE_PROMPT = """You are a ruthless debate strategist. Your goal is to destroy the opponent's case by attacking their specific ideas.

Input: A list of thematic buckets, where each bucket contains a list of specific 'Strategic Ideas'.
Role: You are the {SPEAKER_ROLE}.

Instructions:
Iterate through EVERY specific Idea in each Bucket. For each Idea, generate distinct responses based on your role intensity:
  - If you are a 2nd Speaker: Generate 2 distinct responses for each Idea.
  - If you are a 3rd Speaker: Generate 3 distinct responses for each Idea.

Mandatory Tactics to Use:
1. Worldview Challenge: Rebut the underlying assumption (Characterization). 'They assume X, but the world is actually Y.'
2. The Turn (Flip): Argue the mechanism causes the opposite effect or the impact actually helps YOUR side.
3. Destruction: Direct denial of facts or mitigation of impact.

Output: A mapping:
  - Bucket -> Idea -> [Response 1, Response 2...]
"""

SYNTH_PROMPT = """You are the final speaker delivering a verbal debate speech. You have been given a set of 'Ingredients':
1. Refutations: A map of responses to the enemy's points (if applicable).
2. Constructives: New arguments/extensions to present (if applicable).

Instructions:
1. Weave these ingredients into a cohesive, persuasive speech.
2. Structure:
    - Introduction: Hook + Stance.
    - Rebuttal Section: Systematically go through the Refutations buckets. Use signposting (e.g., 'On their first clash about economics...').
    - Constructive Section: Present your New Arguments clearly (PEEL format).
    - Conclusion: Summarize why your side has won.
3. Tone: Confident, engaging, and spoken-word style.
"""

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
    def __init__(self, lm, speaker_position: str, architecture: str):
        self.lm = lm
        self.speaker_position = speaker_position
        self.architecture = architecture
        self.team = "Proposition" if "prop" in speaker_position else "Opposition"
        self.speaker_number = int(speaker_position.split('_')[1])
        
        # map positions to role names
        roles = {
            "prop_1": "Prime Minister",
            "opp_1": "Leader of Opposition", 
            "prop_2": "Deputy Prime Minister",
            "opp_2": "Deputy Leader of Opposition",
            "prop_3": "Government Whip",
            "opp_3": "Opposition Whip"
        }
        self.role_name = roles.get(speaker_position, "Debater")

    def _call_llm(self, prompt):
        print(f"DEBUG: calling LLM for {self.role_name}...")
        with dspy.context(lm=self.lm):
            response = self.lm(prompt=prompt)
            if isinstance(response, list):
                return response[0] if response else ""
            return response

    def generate_speech(self, motion, teammate_speech, opponent_speeches):
        if self.architecture == "baseline":
            return self._generate_baseline(motion, teammate_speech, opponent_speeches)
        else:
            return self._generate_enhanced(motion, teammate_speech, opponent_speeches)

    def _generate_baseline(self, motion, teammate_speech, opponent_speeches):
        prompt = BASELINE_PROMPTS[self.speaker_position]
        context = f"Motion: {motion}\n\n"
        if teammate_speech:
            context += f"Your Partner's Speech:\n{teammate_speech}\n\n"
        if opponent_speeches:
            context += "Opponent Speeches:\n"
            for i, speech in enumerate(opponent_speeches):
                context += f"Opponent {i+1}:\n{speech}\n\n"
        
        full_prompt = f"{context}{prompt}\n\nYour Speech:"
        return self._call_llm(full_prompt)

    def _generate_enhanced(self, motion, teammate_speech, opponent_speeches):
        # extraction phase - only for speakers 2 and 3
        clustered_threats = ""
        if self.speaker_number in [2, 3]:
            num_buckets = 2 if self.speaker_number == 2 else 3
            opp_transcript = "\n\n".join(opponent_speeches)
            
            extraction_prompt = EXTRACT_PROMPT.format(NUM_BUCKETS=num_buckets)
            extraction_input = f"TRANSCRIPT TO ANALYZE:\n{opp_transcript}\n\nINSTRUCTIONS:\n{extraction_prompt}"
            
            print(f"    [Extraction Layer Active]")
            clustered_threats = self._call_llm(extraction_input)

        # refutation phase
        refutations_map = ""
        if clustered_threats:
            refutation_prompt = REFUTE_PROMPT.format(SPEAKER_ROLE=self.role_name)
            refutation_input = f"THREATS TO DESTROY:\n{clustered_threats}\n\nINSTRUCTIONS:\n{refutation_prompt}"
            
            print(f"    [Refutation Layer Active]")
            refutations_map = self._call_llm(refutation_input)

        # generation phase - only for speakers 1 and 2
        new_case = ""
        if self.speaker_number in [1, 2]:
            generation_input = f"Motion: {motion}\nSide: {self.team}\nRole: {self.role_name}\n"
            if teammate_speech:
                generation_input += f"Teammate's Previous Speech:\n{teammate_speech}\n"
            
            generation_input += f"\nINSTRUCTIONS:\n{ARG_GEN_PROMPT}"
            
            print(f"    [Generation Layer Active]")
            new_case = self._call_llm(generation_input)

        # synthesis phase - combine everything into final speech
        synthesis_input = f"Motion: {motion}\nRole: {self.role_name}\n"
        if refutations_map:
            synthesis_input += f"\nREFUTATION INGREDIENTS:\n{refutations_map}\n"
        if new_case:
            synthesis_input += f"\nCONSTRUCTIVE INGREDIENTS:\n{new_case}\n"
            
        synthesis_input += f"\nINSTRUCTIONS:\n{SYNTH_PROMPT}"
        
        print(f"    [Speech Synthesizer Active]")
        result = self._call_llm(synthesis_input)
        print(f"DEBUG: generated {len(result.split())} words")
        return result

def judge_debate(motion, turns, judge_lm):
    transcript = f"Motion: {motion}\n\n"
    for turn in turns:
        transcript += f"\n--- {turn.team} Speaker {turn.speaker_number} ---\n{turn.speech}\n"
    
    # this prompt is based on WUDC judging criteria
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
    
    # parse scores from response
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
    
    # calculate winner mathematically 
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
    prop_speeches = []
    opp_speeches = []
    
    # speaking order for 3v3 format
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
        
        teammate_speech = None
        opponent_speeches = []
        
        if team == "Proposition":
            if prop_speeches:
                teammate_speech = prop_speeches[-1]
            opponent_speeches = opp_speeches
        else:
            if opp_speeches:
                teammate_speech = opp_speeches[-1]
            opponent_speeches = prop_speeches
            
        print(f"  {team} Speaker {speaker_num} generating speech...")
        speech = speaker.generate_speech(motion, teammate_speech, opponent_speeches)
        
        if team == "Proposition":
            prop_speeches.append(speech)
        else:
            opp_speeches.append(speech)
            
        turns.append(Turn(position, team, speaker_num, speech, arch))
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
    
    # shorthand to full model name mapping
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
    
    # build output data
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
    
    # append to existing csv or create new one
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
