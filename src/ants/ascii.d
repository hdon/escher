module ants.ascii;

// Pseudo-capitalized keyboard keys starting at ascii space (32)
private char[96] shifted = [ ' ', '!', '"', '#', '$', '%', '&', '"', '(', ')', '*', '+', '<', '_', '>', '?', ')', '!', '@', '#', '$', '%', '^', '&', '*', '(', ':', ':', '<', '+', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '{', '|', '}', '^', '_', '~', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '{', '|', '}', '~' ];

char holdShift(char c)
{
  if (c >= ' ' && c <= '~')
    return shifted[c-' '];
  return c;
}

char capsLocked(char c)
{
  if (c >= 'a' && c <= 'z')
    return cast(char)(c - ' ');
  return c;
}
