class ReceiptDraft {
  final String merchant, amount, currency;
  const ReceiptDraft(this.merchant,this.amount,this.currency);
  factory ReceiptDraft.parse(String text) {
    final lines=text.split('\n').map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
    final name=lines.where((s)=>RegExp(r'^(paid to|merchant|billed by)\s*[:\-]?',caseSensitive:false).hasMatch(s)).firstOrNull;
    final amount=RegExp(r'(?:INR|Rs\.?|₹|USD|\$|EUR|€|GBP|£)\s*([\d,]+(?:\.\d{1,2})?)',caseSensitive:false).firstMatch(text);
    final currency=text.contains('₹')||RegExp(r'\b(INR|Rs)\b',caseSensitive:false).hasMatch(text)?'INR':text.contains('€')||RegExp(r'\bEUR\b',caseSensitive:false).hasMatch(text)?'EUR':text.contains('£')||RegExp(r'\bGBP\b',caseSensitive:false).hasMatch(text)?'GBP':text.contains(r'$')||text.contains('USD')?'USD':'INR';
    return ReceiptDraft(name?.replaceFirst(RegExp(r'^(paid to|merchant|billed by)\s*[:\-]?\s*',caseSensitive:false),'')??'',
      amount?.group(1)?.replaceAll(',','')??'',currency);
  }
}
