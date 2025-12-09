MAIN FOLDER

This folder contains the primary debate agent implementation and final experiment results.


FILES

Bhavya_All_Four_Architectures.py
The main debate agent. Implements four architectures: baseline, detailed_prompts, enhanced, and schema_guided. Run debates between any combination of models and architectures.

Kyle_224v_Vertex_Experiments.ipynb
Colab for running similar experiments with Gemini models through Vertex AI.

motions.txt
List of 10 debate motions used in the experiments.

logic_store.json
JSON file containing logic schemas for the schema_guided architecture.

.env
Contains Bhavya's personal OPENAI_API_KEY (we used this once LiteLLM access was cut). Bhavya is sharing this to simplify testing. Bhavya has set budget limits and will change his key once grading finishes.


TESTS SUBFOLDER

Tests/baseline_vs_detailed_prompts/
40 debates comparing baseline vs detailed_prompts architecture.

Tests/baseline_vs_enhanced/
40 debates comparing baseline vs enhanced architecture.

Tests/baseline_vs_schema_guided/
40 debates comparing baseline vs schema_guided architecture.

Tests/architecture_verification_test/
Initial verification tests for architecture correctness.


HOW TO RUN THE DEBATE AGENT

Command line arguments:
-t, --turns         Number of turns (1, 2, or 3). Default: 3
-pm, --prop-model   Model for Proposition. Choices: 4o, 4o-mini, o1, o1-mini. Default: 4o-mini
-om, --opp-model    Model for Opposition. Choices: 4o, 4o-mini, o1, o1-mini. Default: 4o-mini
-pa, --prop-arch    Architecture for Proposition. Choices: baseline, detailed_prompts, enhanced, schema_guided. Default: baseline
-oa, --opp-arch     Architecture for Opposition. Choices: baseline, detailed_prompts, enhanced, schema_guided. Default: enhanced
-jm, --judge-model  Judge model. Choices: o3, o1. Default: o3
-m, --motion        Debate motion text. Default: "This house would make voting mandatory"
-o, --output        Output CSV filename. Default: crossover_debate_results.csv


EXAMPLES

Example 1: Run a full 3-turn debate with gpt-4o vs gpt-4o-mini, enhanced vs baseline
python Bhavya_All_Four_Architectures.py -t 3 -pm 4o -om 4o-mini -pa enhanced -oa baseline

Example 2: Run a 1-turn debate with schema_guided vs detailed_prompts on a custom motion
python Bhavya_All_Four_Architectures.py -t 1 -pm 4o -om 4o -pa schema_guided -oa detailed_prompts -m "This house believes social media does more harm than good"

Example 3: Run baseline vs baseline to compare models directly
python Bhavya_All_Four_Architectures.py -pm 4o -om 4o-mini -pa baseline -oa baseline -o model_comparison.csv
