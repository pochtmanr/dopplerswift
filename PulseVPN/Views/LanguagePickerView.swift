import SwiftUI

struct LanguagePickerView: View {
    @Binding var selectedLanguage: AppLanguage

    var body: some View {
        List {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    selectedLanguage = lang
                } label: {
                    HStack {
                        Text(lang.displayName)
                            .foregroundStyle(Design.Colors.textPrimary)

                        Spacer()

                        if selectedLanguage == lang {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Design.Colors.teal)
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
        .navigationTitle("Language")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        LanguagePickerView(selectedLanguage: .constant(.en))
    }
}
