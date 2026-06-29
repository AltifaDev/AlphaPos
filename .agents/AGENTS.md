# Custom Rules for AlphaPos

## SwiftUI Form State Checklist
Every time you create or modify form input fields (e.g., `TextField`, `DatePicker`, `Toggle`, `Picker`) inside a view, you must verify that the binding variable (e.g. `$dateInput`) is correctly declared with `@State private var ...` at the top level of the View. Follow this checklist during planning and execution:
- [ ] List all state bindings (e.g. `$myVariable`) used in the SwiftUI form.
- [ ] For each binding, verify that `@State private var myVariable` exists at the top level of the View.
- [ ] Ensure the default initialization value matches the expected type of the SwiftUI input field (e.g. `Date()` for `DatePicker`, `""` for `TextField`, `false` for `Toggle`).
