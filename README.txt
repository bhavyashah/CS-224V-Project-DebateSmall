CS 224V PROJECT - DEBATE ARCHITECTURE COMPARISON

This project compares different LLM architectures for British Parliamentary (BP) style debates.
Four architectures are tested: baseline, detailed_prompts, enhanced, and schema_guided.


Main/
Core implementation and final experiments. Contains Bhavya_All_Four_Architectures.py with all four architecture implementations, and the Tests/ subfolder with 120 final debate results (40 debates each for baseline vs detailed_prompts, enhanced, and schema_guided). Also, contains Kyle_224v_Vertex_Experiments.ipynb to do similarly for Gemini models through Vertex AI.

Experiments/
This contains all the code we wrote for the project throughout the quarter. Exploratory notebooks and experimental scripts developed during the quarter. Includes crossover debate implementations, DSPy rubric experiments, Vertex AI experiments, and visualization notebooks for analyzing results.

Preliminary Test Scripts/
PowerShell scripts used during development to orchestrate batch debate runs. Includes scripts for parallel debates, failed debate retries, and various matchup configurations. This is old stuff more for documentation than for you to run.

PreliminaryResults/
CSV files from early experimental runs before the final 120-debate study. Contains baseline results, crossover debate results, DSPy experiments, and architecture comparison tests. This is old stuff to hopefully give you a sense of how we iterated on our prompts and architectures based on testing.

224V-7.pdf
Kyle's final draft of the report, which the final submitted report is based on.
