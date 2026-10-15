final RegExp _visible = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Si el texto contiene al menos una letra o un dígito. Los nombres hechos
/// solo de espacios, signos o caracteres invisibles (p. ej. U+200B) se
/// tratan como vacíos, igual que en las reglas de Firestore.
bool hasVisibleContent(String text) => _visible.hasMatch(text);
