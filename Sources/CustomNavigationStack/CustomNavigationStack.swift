//
//  CustomNavigationStack.swift
//  CustomNavigationStack
//
//  Created by Quentin Fasquel on 21/01/2024.
//

import SwiftUI

public struct CustomNavigationStack<Root: View>: View {
    @State private var destinations: [AnyNavigationDestination] = []
    @State private var interactiveTransition = InteractivePopTransition()

    @Binding var path: CustomNavigationPath
    @ViewBuilder var root: () -> Root

    public init(path: Binding<CustomNavigationPath>, @ViewBuilder root: @escaping () -> Root) {
        self._path = path
        self.root = root
    }

    public var body: some View {
        ZStack {
            if interactiveTransition.isInteractive {
                previousView
                    .offset(x: -100 * (1 - interactiveTransition.progress))
                    .id("z-\(currentIndex - 1)")
            }
            
            currentView
                .id("z-\(currentIndex)")
                .zIndex(Double(currentIndex))
                .transition(.navigationSlide(forward: $path.isForward))
                .modifier(InteractivePopGestureModifier(
                    path: $path,
                    transition: $interactiveTransition
                ))
                .onAppear {
                    interactiveTransition.isAnimating = false
                }
        }
        .animation(.default, value: path)
        .onChange(of: path) { _, newValue in
            if !interactiveTransition.isInteractive {
                interactiveTransition.isAnimating = true
            }
        }
        .transaction(value: path) { transaction in
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                interactiveTransition.isAnimating = false
            }
        }
    }

    private var navigationBar: some View {
        HStack {
            Button(action: pop) {
                Image(systemName: "arrow.left")
                    .padding()
                    .background { Circle().fill(Color.black) }
            }
            .contentShape(Circle())
            .onTapGesture { }

            Spacer()
        }
        .padding()

    }
    
    private var currentIndex: Int { path.count }
    
    private var previousItem: (any Hashable)? {
        currentIndex > 1 ? path.items[currentIndex - 2] : nil
    }

    private var currentItem: (any Hashable)? {
        currentIndex > 0 ? path.items[currentIndex - 1] : nil
    }

    @ViewBuilder private var previousView: some View {
        if currentIndex > 0 {
            itemView(for: currentIndex - 1, item: previousItem)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private var currentView: some View {
        if currentIndex > 0, currentItem != nil {
            itemView(for: currentIndex, item: currentItem)
        } else {
            itemView(for: currentIndex, item: nil)
        }
    }

    @ViewBuilder func itemView(for index: Int, item: (any Hashable)?) -> some View {
        if let item {
            destinationView(for: item)
                .id("\(item)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background()
                .safeAreaInset(edge: .top) {
                    navigationBar
                }
        } else {
            root()
                .id("root")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background()
                .safeAreaInset(edge: .top) {
                    navigationBar.hidden()
                }
                .onPreferenceChange(NavigationDestinationPreferenceKey.self) { values in
                    destinations = values
                }
        }
    }

    func pop() {
        path.removeLast()
    }
    
    fileprivate func destination<T: Hashable>(for item: T) -> ItemDestination<T> {
        destinations.compactMap { $0.base as? ItemDestination<T> }.first!
    }

    @ViewBuilder func destinationView<T: Hashable>(for item: T) -> AnyView {
        destination(for: item).makeView(item)
    }
}

// MARK: - Navigation Path

public struct CustomNavigationPath: Hashable {

    fileprivate var items: [any Hashable] = []
    public var count: Int { items.count }

    fileprivate var isForward: Bool = true

    public init(_ elements: [any Hashable] = []) {
        self.items = elements
    }

    public mutating func append(_ item: any Hashable) {
        isForward = true
        items.append(item)
    }

    public mutating func removeLast() {
        if items.isEmpty {
            return
        }
        isForward = false
        items.removeLast()
    }
    
    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        items.forEach {
            hasher.combine($0)
        }
    }

    // MARK: Equatable

    public static func == (lhs: CustomNavigationPath, rhs: CustomNavigationPath) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

// MARK: - Navigation Destination

fileprivate protocol NavigationDestination {}

fileprivate struct ItemDestination<T: Hashable>: NavigationDestination {
    var type: T.Type { T.self }
    var viewBuilder: (T) -> any View

    func makeView(_ item: T) -> AnyView {
        AnyView(viewBuilder(item))
    }

    static func == (lhs: ItemDestination<T>, rhs: ItemDestination<T>) -> Bool {
        true
    }
}

fileprivate struct AnyNavigationDestination: Equatable {
    var base: NavigationDestination
    
    static func == (lhs: AnyNavigationDestination, rhs: AnyNavigationDestination) -> Bool {
        type(of: lhs) == type(of: rhs)
    }
}

// MARK: -

extension View {
    
    public func customNavigationDestination<T: Hashable, V: View>(for item: T.Type, @ViewBuilder _ viewBuilder: @escaping (T) -> V) -> some View {
        let destination = ItemDestination(viewBuilder: viewBuilder)
        return self.transformPreference(NavigationDestinationPreferenceKey.self) { value in
            value += [AnyNavigationDestination(base: destination)]
        }
    }
}

fileprivate enum NavigationDestinationPreferenceKey: PreferenceKey {

    static let defaultValue: [AnyNavigationDestination] = []

    static func reduce(
        value: inout [AnyNavigationDestination],
        nextValue: () -> [AnyNavigationDestination]
    ) {
        value += nextValue()
    }
}


// MARK: - Navigation Slide Transition

struct NavigationSlideModifier: ViewModifier {
    fileprivate enum NavigationContext {
        case insertion, removal, identity
    }

    fileprivate var context: NavigationContext
    @Binding var forward: Bool
    @Binding var progress: CGFloat

    var offsetX: CGFloat {
        switch context {
        case .insertion:
            return progress * (forward ? UIScreen.main.bounds.width : -100)
        case .removal:
            return progress * (forward ? -100 : UIScreen.main.bounds.width)
        case .identity:
            return 0
        }
    }

    func body(content: Content) -> some View {
        content.offset(x: offsetX)
    }
}

extension AnyTransition {
    public static func navigationSlide(
        forward: Binding<Bool>,
        progress: Binding<CGFloat> = .constant(1)
    ) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: NavigationSlideModifier(
                    context: .insertion,
                    forward: forward,
                    progress: progress
                ),
                identity: NavigationSlideModifier(
                    context: .identity,
                    forward: .constant(true),
                    progress: .constant(0)
                )
            ),
            removal: .modifier(
                active: NavigationSlideModifier(
                    context: .removal,
                    forward: forward,
                    progress: progress
                ),
                identity: NavigationSlideModifier(
                    context: .identity,
                    forward: .constant(true),
                    progress: .constant(0)
                )
            )
        )
    }
}


// MARK: - Interactive Pop Gesture

struct InteractivePopTransition: Equatable {
    var isInteractive: Bool = false
    var isAnimating: Bool = true
    var progress: CGFloat = 0
}

struct InteractivePopGestureModifier: ViewModifier {
    struct DraggingState: Hashable {
        var delta: CGFloat = 0
        var translation: CGFloat = 0
    }

    @GestureState private var draggingState = DraggingState()
    private var screenWidth: CGFloat { UIScreen.main.bounds.size.width }

    @Binding var path: CustomNavigationPath
    @Binding var transition: InteractivePopTransition
    var complete: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        if path.count < 1 {
            content
        } else {
            content
                .offset(x: transition.progress * screenWidth, y: 0)
                .gesture(popGesture)
                .onChange(of: draggingState) { _, state in
                    let candidate = transition.progress - state.delta / screenWidth
                    if candidate > 0, candidate < 1 {
                        transition.isInteractive = true
                        transition.progress = candidate
                    }
                }
        }
    }

    var popGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($draggingState) { value, state, transaction in
                if value.startLocation.x < 30 {
                    state.delta = state.translation - value.translation.width
                    state.translation = value.translation.width
                }
            }
            .onEnded { value in
                guard transition.isInteractive else {
                    return
                }

                if transition.progress > 0.75 || value.velocity.width > 2 {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        transition.progress = 1
                    } completion: {
                        pop()
                        reset()
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        transition.progress = 0
                    } completion: {
                        reset()
                    }
                }
            }
    }

    func pop() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            path.removeLast()
        }
    }

    func reset() {
        transition.isAnimating = false
        transition.isInteractive = false
        transition.progress = 0
    }
}


