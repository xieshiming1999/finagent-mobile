const description =
    'Asks the user questions to gather information, clarify ambiguity, or offer choices.';

const prompt =
    '''Use this tool when you need to ask the user questions during execution. This allows you to:
1. Gather user preferences or requirements
2. Clarify ambiguous instructions
3. Get decisions on implementation choices as you work
4. Offer choices to the user about what direction to take.

Usage notes:
- Users will always be able to select "Other" to provide custom text input
- Use multiSelect: true to allow multiple answers to be selected for a question
- If you recommend a specific option, make that the first option in the list and add "(Recommended)" at the end of the label
- If execution cannot proceed without the user's answer, call this tool instead of writing a normal assistant message that only lists questions.
- For guarded finance actions such as buy, sell, transfer, order sizing, broker/simulation choice, portfolio choice, price assumption, or final approval, this tool is the required clarification checkpoint when any required field is missing.

Plan mode note: In plan mode, use this tool to clarify requirements or choose between approaches BEFORE finalizing your plan.''';
