# OSS-Fuzz: Continuous Fuzzing for Open Source Software
- collect result strings using /src/results.sh
- post process them to get output and crashing inputs stored on the host mounted FS
- optionally run `symenable` before previous step to symbolize reports as well
- harnesses are NOT stored