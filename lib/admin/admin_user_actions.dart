/// The confirmation each action on an account needs, in one place so the list
/// screen and the detail screen ask the same question in the same words.
///
/// Only the asking lives here. The call itself stays with the screen, which is
/// what owns the row afterwards and the `guard` that turns a refusal —
/// `nickname_taken`, a network that is down — into a line the admin can read.
library;

import 'package:flutter/material.dart';

import 'admin_models.dart';
import 'admin_widgets.dart';

/// Returns the reason to ban with, `''` for none, or null when the admin backed
/// out. Empty and cancelled are deliberately different answers: the reason is
/// optional, so "" is a real one.
Future<String?> askBanReason(BuildContext context, AdminUserRow user) => adminPrompt(
      context,
      title: 'Akkauntni bloklash',
      message: '${user.label} (#${user.id}) bloklanadi: joriy jangdan va soketdan chiqariladi, '
          'barcha tokenlari darhol o‘chadi va u qayta kira olmaydi.\n\n'
          'Sabab (ixtiyoriy, jurnalga yoziladi):',
      hint: 'Masalan: haqoratli taxallus',
      confirmLabel: 'Bloklash',
      destructive: true,
    );

Future<bool> askUnban(BuildContext context, AdminUserRow user) => adminConfirm(
      context,
      title: 'Blokni olish',
      message: '${user.label} (#${user.id}) akkauntiga qaytadan kirish ochiladi. Davom etilsinmi?',
      confirmLabel: 'Blokni olish',
      destructive: false,
    );

/// Returns the new nickname, or null when the admin backed out. The server
/// holds it to the same rules as the onboarding field, so an invalid or taken
/// name comes back as an error for the screen to show.
Future<String?> askNickname(BuildContext context, AdminUserRow user) => adminPrompt(
      context,
      title: "Taxallusni o'zgartirish",
      message: '${user.label} (#${user.id}) uchun yangi taxallus. '
          'Qoidalar o‘yindagi bilan bir xil, band nom qabul qilinmaydi.',
      hint: 'yangi_taxallus',
      initial: user.nickname ?? '',
      confirmLabel: "O'zgartirish",
      required: true,
    );
