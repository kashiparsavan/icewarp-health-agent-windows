# PROJECT RULES & CONSTRAINTS

## 1. STRICT LOGIC RULES (Windows Parity)
- **Intrusion Prevention:** Block IP connections expected value is **50**. Block duration expected value is **360** minutes.
- **Admin Email:** If empty or missing = **CRITICAL**. If invalid = **WARN**. Never output INFO for this.
- **DIGEST-MD5:** Must be `true` (enabled) = **CRITICAL**. `false` (disabled) = **PASS**. Missing = **CRITICAL**.
- **IMAP / POP3:** Running (1/Enabled) = **PASS**. Disabled (0/Disabled) = **WARN**.
- **Database:** MySQL = **PASS**. SQLite = **WARN**.
- **License:** If `C_License_TrialExpire` is empty, fallback to parsing `license.xml`. Never assume perpetual.
- **Formatting:** Disk = `Total(GB)=X / Used %=Y`. RAM = `Total(KB)=X / Available KB=Y`.
- **JSON:** Output must strictly match the 411-key schema. Empty strings -> null, true/false -> bool, numeric strings -> numbers.

## 2. CODE STYLE
- PowerShell 5.1 compatible.
- Do not use Bash or call Linux scripts.
- Ensure all `.ps1` files use CRLF line endings.

## 3. MULTI-AGENT COMMUNICATION PROTOCOL
- **OMP** acts as the Supervisor and writes instructions to `agents_bridge.md` under the `## TASK_FOR_OPENCODE` section.
- **OpenCode** acts as the Worker. It checks `agents_bridge.md`, executes tasks under `## TASK_FOR_OPENCODE`, and writes results under `## RESULT_FOR_OMP`.
- Never delete previous tasks or results; always append to the file.

### ?? TASK LIFECYCLE & REAL-TIME LOGGING
1. **Task Assignment (OMP):** Every task must have a unique ID (e.g., `TASK-001`) and a Status tag (`[STATUS: ASSIGNED]`). OMP writes instructions under this tag.
2. **Worker Acknowledgement (OpenCode):** Upon picking up the task, OpenCode must update the status to `[STATUS: IN_PROGRESS]`.
3. **Real-time Logging (OpenCode):** While working, OpenCode must append short progress updates (e.g., `- [HH:MM] Reading file X`, `- [HH:MM] Running tests`) under a `### Execution Logs` section for that task.
4. **Completion (OpenCode):** When done, OpenCode changes the status to `[STATUS: DONE]` and writes the final report under `### Final Result`.
5. **Review (OMP):** OMP reads the logs and the final result, then updates the status to `[STATUS: VERIFIED]`.
6. **Error Handling & Blocking (OpenCode):** If OpenCode encounters a fatal error (e.g., rate limit, missing file) that it cannot resolve, it MUST change the status to `[STATUS: BLOCKED]` and write the exact error message under `### Blocking Issue` so OMP can intervene.
7. **Review & Handoff Loop (OMP):** If OMP reviews the `### Final Result` and finds it insufficient, OMP MUST create a new task section (e.g., `## TASK-002: Fix review issues`) with `[STATUS: ASSIGNED]` and provide specific feedback. Do not rewrite the worker's code yourself.
8. **Immutable History:** Under NO circumstances should either agent delete previous tasks, logs, or results from `agents_bridge.md`. Always append new tasks and status updates to the end of the file.
9. **AUTONOMOUS POLLING LOOP (OMP):** OMP must act as an autonomous supervisor. If OMP reads `agents_bridge.md` and sees `[STATUS: IN_PROGRESS]`, OMP MUST NOT close its session. Instead, OMP must execute a shell command to sleep and re-check:
   `Start-Sleep -Seconds 120; Get-Content agents_bridge.md`
   - OMP will wait 2 minutes, then read the updated file.
   - If it is STILL `[STATUS: IN_PROGRESS]`, OMP MUST repeat the sleep command and check again.
   - OMP must repeat this loop up to 10 times (20 minutes max).
   - ONLY when OMP sees `[STATUS: DONE]`, it stops looping, reads the `### Final Result`, and proceeds to review and assign the next task.
   - This ensures the agents work asynchronously without human intervention and without burning LLM tokens in an infinite `Wait` loop.
10. **WINDOWS SHELL ENVIRONMENT:** The agents are running on Windows (PowerShell), NOT Linux. 
   - NEVER use `cat`, `echo >`, `<<EOF`, or other bash-specific commands.
   - To append to a file, ALWAYS use the native `Write` tool to overwrite the whole file, or use PowerShell `Add-Content`.
11. **STALLED WORKER & TOKEN EXHAUSTION HANDLING (OMP):**
   - If OMP sees `[STATUS: IN_PROGRESS]`, it must check the `### Execution Logs` timestamps.
   - If no new log has been added in the last 15 minutes (or if 5 polling cycles pass with no changes), OMP MUST assume the worker (OpenCode) has hit a rate limit, ran out of tokens, or crashed.
   - **Action:** OMP must change the status to `[STATUS: STALLED]`.
   - OMP must then STOP polling and tell the human user: *"Worker seems stalled. Please check OpenCode's UI for token limits. I am pausing for 10 minutes."*
   - OMP must then use PowerShell to wait: `Start-Sleep -Seconds 600` (NOT bash `sleep`). After 10 minutes, it can check again.