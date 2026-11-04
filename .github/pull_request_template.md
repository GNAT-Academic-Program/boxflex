   ## What this changes
   <!-- One or two sentences. -->

   ## Planner card
   <!-- e.g. BF-23 -->

   ## Checklist
   - [ ] Branched from an up-to-date `main`
   - [ ] `alr build` passes in the repo root
   - [ ] `cd tests && alr build && ./bin/tests` prints `all tests passed`
   - [ ] Showcase still builds and runs (`cd showcase && alr build && alr run`) if `src/` changed
   - [ ] New behavior has a test
   - [ ] No floating point, access types or heap in `src/`
   - [ ] Contracts were not weakened or turned off to make something pass
   - [ ] I did not commit the `gnatprove` line that `alr with gnatprove` adds to `alire.toml`
   - [ ] Base repository is **emmabellerogo/boxflex**, not GNAT-Academic-Program