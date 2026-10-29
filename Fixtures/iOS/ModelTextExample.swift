// Complete application fixture for the model-owned text example in Examples/Size-Caches.md.
import DerivedKeysUI
import UIKit

struct Article {
    var text: String
}

@MainActor
final class ArticleView: UIView {
    var model: Article {
        didSet {
            textView.text = model.text
            setNeedsLayout()
        }
    }
    let textView = UITextView()

    init(model: Article) {
        self.model = model
        super.init(frame: .zero)
        textView.font = .systemFont(ofSize: 17)
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.semanticContentAttribute = .forceLeftToRight
        textView.text = model.text
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
    }
}

@MainActor
func makeArticleTextSizes() -> SizeCache<ArticleView> {
    SizeCache<ArticleView>(
        dependingOn: \.model.text,
        \.textView.font,
        capacity: 256
    ) { view, proposal in
        view.textView.sizeThatFits(proposal)
    }
}

@MainActor
func modelTextExample() {
    // Retain this handle in the application's chosen owner for subsequent requests.
    let textSizes = makeArticleTextSizes()
    let view = ArticleView(model: Article(text: "A native Swift model owns this text."))
    let proposal = CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
    _ = textSizes.size(of: view, toFit: proposal)
    view.model.text += " An edit updates the rendered text before the next lookup."
    _ = textSizes.size(of: view, toFit: proposal)
}
