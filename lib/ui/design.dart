import 'dart:ui';
import 'package:flutter/material.dart';

const accentColours = <String, Color>{
  'Teal': Color(0xff17645d), 'Blue': Color(0xff315da8),
  'Violet': Color(0xff7550a8), 'Rose': Color(0xffa7466a),
  'Amber': Color(0xff8f641b), 'Forest': Color(0xff386e42),
  'Slate': Color(0xff526273), 'Coral': Color(0xffa44e37),
};

@immutable
class VaultStyle extends ThemeExtension<VaultStyle> {
  final bool glass, motion;
  final String language;
  const VaultStyle({this.glass = false, this.motion = true, this.language = 'en'});
  @override
  VaultStyle copyWith({bool? glass, bool? motion, String? language}) => VaultStyle(
    glass: glass ?? this.glass, motion: motion ?? this.motion, language: language ?? this.language);
  @override
  VaultStyle lerp(covariant VaultStyle? other, double t) =>
    other == null || t < .5 ? this : other;
}
Duration motionDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    !(Theme.of(context).extension<VaultStyle>()?.motion ?? true)
    ? Duration.zero : const Duration(milliseconds: 220);

class VaultCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  const VaultCard({super.key, required this.child, this.margin, this.color});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = theme.extension<VaultStyle>()?.glass ?? false;
    final base = color ?? theme.colorScheme.surface;
    final body = AnimatedContainer(duration: motionDuration(context),
      decoration: BoxDecoration(
        color: glass ? null : base,
        gradient: glass ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [base.withValues(alpha: .90), theme.colorScheme.primaryContainer.withValues(alpha: .68)]) : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: glass ? .65 : .45))),
      child: Material(type: MaterialType.transparency, child: child));
    return Padding(padding: margin ?? const EdgeInsets.only(bottom: 12),
      child: ClipRRect(borderRadius: BorderRadius.circular(20),
        child: glass ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: body) : body));
  }
}

class VaultPageTransitions extends PageTransitionsBuilder {
  const VaultPageTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (motionDuration(context) == Duration.zero) { return child; }
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(opacity: eased, child: SlideTransition(
      position: Tween<Offset>(begin: const Offset(.04, 0), end: Offset.zero).animate(eased), child: child));
  }
}

class VaultTextScaler extends TextScaler {
  final TextScaler system;
  final double factor;
  const VaultTextScaler(this.system,this.factor);
  @override double scale(double fontSize) => system.scale(fontSize)*factor;
  @override double get textScaleFactor => system.scale(14)/14*factor;
}

String tr(BuildContext context,String text) {
  if (Theme.of(context).extension<VaultStyle>()?.language != 'ta') return text;
  return const <String,String>{
    'Home':'முகப்பு','Doc':'ஆவணம்','Sub':'சந்தா','Notes':'குறிப்பு','Plan':'திட்டம்',
    'Your vault':'உங்கள் சேமிப்பு','Documents':'ஆவணங்கள்','Subscriptions':'சந்தாக்கள்','Planner':'திட்டங்கள்',
    'Add':'சேர்','Save':'சேமி','Cancel':'ரத்து','Close':'மூடு','Settings':'அமைப்புகள்',
    'Appearance':'தோற்றம்','Security':'பாதுகாப்பு','Reminders':'நினைவூட்டல்கள்','Backup':'காப்புப்பிரதி',
    'Preferences':'விருப்பங்கள்','Guide':'வழிகாட்டி','Personalize':'தனிப்பயனாக்கு','Storage':'சேமிப்பிடம்',
    'Search vault':'தேடுக','All':'அனைத்தும்','Favorites':'விருப்பங்கள்','Upcoming':'வரவிருப்பவை',
    'Expiring':'காலாவதி','Completed':'முடிந்தவை','Archive':'காப்பகம்','Trash':'குப்பை',
    'All folders':'அனைத்து கோப்புறைகள்','Show':'காட்டு','Name':'பெயர்','Recent':'சமீபத்தியவை','Due':'கெடு',
    'Nothing here yet':'இன்னும் எதுவும் இல்லை','No matches':'முடிவுகள் இல்லை','Use Add to save an item.':'புதிய பதிவைச் சேர்க்க சேர் என்பதைத் தட்டவும்.',
    'Files':'கோப்புகள்','Files & versions':'கோப்புகள் மற்றும் பதிப்புகள்','Organize & reminders':'ஒழுங்கமைப்பு மற்றும் நினைவூட்டல்கள்',
    'Tools':'கருவிகள்','Tools & templates':'கருவிகள் மற்றும் மாதிரிகள்','Lock vault':'பூட்டு',
    'Done':'முடிந்தது','Paid':'செலுத்தப்பட்டது','Dismiss':'நீக்கு','Snooze':'பின்னர் நினைவூட்டு',
    'Glass cards':'கண்ணாடித் தோற்றம்','Animations':'அசைவுகள்','Theme':'தோற்ற வகை',
    'Change PIN':'PIN மாற்று','Set PIN':'PIN அமை','Biometrics first':'முதலில் உயிரளவியல்',
    'Recovery code':'மீட்புக் குறியீடு','Turn off lock':'பூட்டை அணை','Block screenshots':'திரைப்பிடிப்பைத் தடு',
    'Save backup':'காப்புப்பிரதியைச் சேமி','Restore backup':'காப்புப்பிரதியை மீட்டமை',
  }[text] ?? text;
}
