// Native AX flags may be booleans or numbers. Unknown/missing values keep
// their existing permissive semantics; only explicit false/zero is negative.
export const axFlagIsFalse = value => value === false || value === 0;
