//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AppSettingsViewController: OWSTableViewController2 {

    class func inModalNavigationController() -> OWSNavigationController {
        OWSNavigationController(rootViewController: AppSettingsViewController())
    }

    class func inModalViewController() -> UIViewController {
#if targetEnvironment(macCatalyst)
        AppSettingsSplitViewController(appSettingsViewController: AppSettingsViewController())
#else
        inModalNavigationController()
#endif
    }

    private var localUsernameState: Usernames.LocalUsernameState!
    private var localUserProfile: OWSUserProfile?
    private weak var detailNavigationController: OWSNavigationController?
    private var selectsProfileInitially = false
    private var isHostedInStandaloneWindow = false

    override func viewDidLoad() {
#if targetEnvironment(macCatalyst)
        if detailNavigationController != nil {
            backgroundStyle = .clear
            tableViewStyle = .plain
            selectionBehavior = .actionWithoutAutoDeselect
            defaultSpacingBetweenSections = 8
        }
#endif

        super.viewDidLoad()

#if targetEnvironment(macCatalyst)
        if detailNavigationController != nil {
            tableView.insetsContentViewsToSafeArea = false
        }
#endif

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            updateLocalUserProfile(tx: tx)
            localUsernameState = DependenciesBridge.shared.localUsernameManager
                .usernameState(tx: tx)
        }

        title = OWSLocalizedString("SETTINGS_NAV_BAR_TITLE", comment: "Title for settings activity")
#if targetEnvironment(macCatalyst)
        updateCloseButton()
#else
        navigationItem.rightBarButtonItem = .doneButton(dismissingFrom: self)
#endif

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        updateHasExpiredGiftBadge()
        updateTableContents()

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        if let localAci = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci {
            Task {
                let profileFetcher = SSKEnvironment.shared.profileFetcherRef
                _ = try? await profileFetcher.fetchProfile(for: localAci, context: .init(isOpportunistic: true))
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localProfileDidChange),
            name: UserProfileNotifications.localProfileDidChange,
            object: nil,
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localNumberDidChange),
            name: .localNumberDidChange,
            object: nil,
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subscriptionStateDidChange),
            name: DonationReceiptCredentialRedemptionJob.didSucceedNotification,
            object: nil,
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hasExpiredGiftBadgeDidChange),
            name: .hasExpiredGiftBadgeDidChangeNotification,
            object: nil,
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

#if targetEnvironment(macCatalyst)
        if selectsProfileInitially, tableView.indexPathForSelectedRow == nil {
            tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)
        }
#endif
    }

    fileprivate func configureForSplitView(
        detailNavigationController: OWSNavigationController,
        selectsProfileInitially: Bool,
    ) {
        self.detailNavigationController = detailNavigationController
        self.selectsProfileInitially = selectsProfileInitially
    }

#if targetEnvironment(macCatalyst)
    fileprivate func prepareForStandaloneWindow() {
        isHostedInStandaloneWindow = true
        if isViewLoaded {
            updateCloseButton()
        }
    }

    private func updateCloseButton() {
        if isHostedInStandaloneWindow {
            navigationItem.leftBarButtonItem = nil
        } else {
            navigationItem.leftBarButtonItem = .closeButton { [weak self] in
                self?.dismiss(animated: true)
            }
        }
    }
#endif

    fileprivate func makeProfileSettingsViewController() -> ProfileSettingsViewController {
        ProfileSettingsViewController(
            usernameChangeDelegate: self,
            usernameLinkScanDelegate: self,
        )
    }

    private var settingsNavigationController: OWSNavigationController? {
        detailNavigationController ?? owsNavigationController
    }

    private func showSettingsViewController(_ viewController: UIViewController) {
        if let detailNavigationController {
            detailNavigationController.setViewControllers([viewController], animated: false)
            splitViewController?.show(.secondary)
        } else {
            navigationController?.pushViewController(viewController, animated: true)
        }
    }

    private func updateLocalUserProfile(tx: DBReadTransaction) {
        let profileManager = SSKEnvironment.shared.profileManagerRef
        self.localUserProfile = profileManager.localUserProfile(tx: tx)
    }

    @objc
    private func localProfileDidChange() {
        AssertIsOnMainThread()

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        databaseStorage.read(block: updateLocalUserProfile(tx:))
        updateTableContents()
    }

    @objc
    private func localNumberDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    @objc
    private func subscriptionStateDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }

    private var hasExpiredGiftBadge: Bool = false

    private func updateHasExpiredGiftBadge() {
        self.hasExpiredGiftBadge = DonationSettingsViewController.shouldShowExpiredGiftBadgeSheetWithSneakyTransaction()
    }

    @objc
    private func hasExpiredGiftBadgeDidChange() {
        AssertIsOnMainThread()

        let oldValue = self.hasExpiredGiftBadge
        self.updateHasExpiredGiftBadge()
        if oldValue != self.hasExpiredGiftBadge {
            self.updateTableContents()
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    func updateTableContents() {
        let db = DependenciesBridge.shared.db
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let isPrimaryDevice = db.read { tx in
            tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? false
        }

        let contents = OWSTableContents()

        let profileSection = OWSTableSection(items: [
            OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self else { return UITableViewCell() }
                    return self.profileCell()
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    self.showSettingsViewController(self.makeProfileSettingsViewController())
                },
            ),
        ])
        contents.add(profileSection)

        let section1 = OWSTableSection()
        section1.add(.disclosureItem(
            icon: .settingsAccount,
            withText: OWSLocalizedString("SETTINGS_ACCOUNT", comment: "Title for the 'account' link in settings."),
            actionBlock: { [weak self] in
                let vc = AccountSettingsViewController()
                self?.showSettingsViewController(vc)
            },
        ))
        if isPrimaryDevice {
            section1.add(.disclosureItem(
                icon: .settingsLinkedDevices,
                withText: OWSLocalizedString("LINKED_DEVICES_TITLE", comment: "Menu item and navbar title for the device manager"),
                actionBlock: { [weak self] in
                    self?.showSettingsViewController(LinkedDevicesHostingController())
                },
            ))
        }
        section1.add(.init(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            let accessoryContentView: UIView?
            if self.hasExpiredGiftBadge {
                let imageView = UIImageView(image: UIImage(imageLiteralResourceName: "info-fill"))
                imageView.tintColor = Theme.accentBlueColor
                imageView.autoSetDimensions(to: CGSize(square: 24))
                accessoryContentView = imageView
            } else {
                accessoryContentView = nil
            }
            return OWSTableItem.buildCell(
                icon: .settingsDonate,
                itemName: OWSLocalizedString("SETTINGS_DONATE", comment: "Title for the 'donate to signal' link in settings."),
                accessoryType: .disclosureIndicator,
                accessoryContentView: accessoryContentView,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donate"),
            )
        }, actionBlock: { [weak self] in
            self?.didTapDonate()
        }))
        contents.add(section1)

        let section2 = OWSTableSection()
        section2.add(.disclosureItem(
            icon: .settingsAppearance,
            withText: OWSLocalizedString("SETTINGS_APPEARANCE_TITLE", comment: "The title for the appearance settings."),
            actionBlock: { [weak self] in
                let vc = AppearanceSettingsTableViewController()
                self?.showSettingsViewController(vc)
            },
        ))
        section2.add(.disclosureItem(
            icon: .settingsChats,
            withText: OWSLocalizedString("SETTINGS_CHATS", comment: "Title for the 'chats' link in settings."),
            actionBlock: { [weak self] in
                let vc = ChatsSettingsViewController()
                self?.showSettingsViewController(vc)
            },
        ))
        section2.add(.disclosureItem(
            icon: .settingsStories,
            withText: OWSLocalizedString(
                "STORY_SETTINGS_TITLE",
                comment: "Label for the stories section of the settings view",
            ),
            actionBlock: { [weak self] in
                let vc = StoryPrivacySettingsViewController()
                self?.showSettingsViewController(vc)
            },
        ))
        section2.add(.disclosureItem(
            icon: .settingsNotifications,
            withText: OWSLocalizedString("SETTINGS_NOTIFICATIONS", comment: "The title for the notification settings."),
            actionBlock: { [weak self] in
                let vc = NotificationSettingsViewController()
                self?.showSettingsViewController(vc)
            },
        ))
        section2.add(.disclosureItem(
            icon: .settingsPrivacy,
            withText: OWSLocalizedString("SETTINGS_PRIVACY_TITLE", comment: "The title for the privacy settings."),
            actionBlock: { [weak self] in
                let vc = PrivacySettingsViewController()
                self?.showSettingsViewController(vc)
            },
        ))

        if isPrimaryDevice {
            section2.add(.disclosureItem(
                icon: .backup,
                withText: OWSLocalizedString(
                    "SETTINGS_BACKUPS",
                    comment: "Label for the 'backups' section of app settings.",
                ),
                addBetaLabel: false,
                actionBlock: { [weak self] in
                    guard
                        let self,
                        let settingsNavigationController
                    else { return }

                    let backupsViewController: UIViewController
                    if BuildFlags.LocalFileBackups.settingsUI {
                        backupsViewController = BackupSettingsLandingPageViewController()
                    } else {
                        let shouldSkipOnboarding = DependenciesBridge.shared.db.read { tx in
                            if BackupSettingsStore().shouldOverrideShowBackupsOnboarding(tx: tx) {
                                return false
                            }
                            return BackupSettingsStore().haveBackupsEverBeenEnabled(tx: tx)
                        }

                        backupsViewController = BackupOnboardingCoordinator(
                            backupType: .remote,
                        ).prepareForPresentation(
                            inNavController: settingsNavigationController,
                            shouldSkipOnboarding: shouldSkipOnboarding,
                        )
                    }

                    self.showSettingsViewController(backupsViewController)
                },
            ))
        } else {
            section2.add(.disclosureItem(
                icon: .backup,
                withText: OWSLocalizedString(
                    "SETTINGS_BACKUPS",
                    comment: "Label for the 'backups' section of app settings.",
                ),
                addBetaLabel: false,
                actionBlock: { [weak self] in
                    self?.showSettingsViewController(LinkedDeviceBackupSettingsViewController())
                },
            ))
        }
        section2.add(.disclosureItem(
            icon: .settingsDataUsage,
            withText: OWSLocalizedString("SETTINGS_DATA", comment: "Label for the 'data' section of the app settings."),
            actionBlock: { [weak self] in
                let vc = DataSettingsTableViewController()
                self?.showSettingsViewController(vc)
            },
        ))
        contents.add(section2)

        if SUIEnvironment.shared.paymentsRef.shouldShowPaymentsUI {
            let paymentsSection = OWSTableSection()
            paymentsSection.add(.init(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.preservesSuperviewLayoutMargins = true
                    cell.contentView.preservesSuperviewLayoutMargins = true

                    var subviews = [UIView]()

                    let iconView = OWSTableItem.imageView(
                        forIcon: .settingsPayments,
                        tintColor: nil,
                        iconSize: OWSTableItem.iconSize,
                    )
                    iconView.setCompressionResistanceHorizontalHigh()
                    subviews.append(iconView)
                    subviews.append(UIView.spacer(withWidth: OWSTableItem.iconSpacing))

                    let nameLabel = UILabel()
                    nameLabel.text = OWSLocalizedString(
                        "SETTINGS_PAYMENTS_TITLE",
                        comment: "Label for the 'payments' section of the app settings.",
                    )
                    nameLabel.textColor = Theme.primaryTextColor
                    nameLabel.font = OWSTableItem.primaryLabelFont
                    nameLabel.adjustsFontForContentSizeCategory = true
                    nameLabel.numberOfLines = 0
                    nameLabel.lineBreakMode = .byWordWrapping
                    nameLabel.setContentHuggingLow()
                    nameLabel.setCompressionResistanceHigh()
                    subviews.append(nameLabel)

                    subviews.append(UIView.hStretchingSpacer())

                    let unreadPaymentsCount = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                        PaymentFinder.unreadCount(transaction: transaction)
                    }
                    if unreadPaymentsCount > 0 {
                        let unreadLabel = UILabel()
                        unreadLabel.text = OWSFormat.formatUInt(min(9, unreadPaymentsCount))
                        unreadLabel.font = .dynamicTypeSubheadlineClamped
                        unreadLabel.textColor = .ows_white

                        let unreadBadge = OWSLayerView.circleView()
                        unreadBadge.backgroundColor = .ows_accentBlue
                        unreadBadge.addSubview(unreadLabel)
                        unreadLabel.autoCenterInSuperview()
                        unreadLabel.autoPinEdge(toSuperviewEdge: .top, withInset: 3)
                        unreadLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
                        unreadBadge.autoPinToSquareAspectRatio()
                        unreadBadge.setContentHuggingHorizontalHigh()
                        unreadBadge.setCompressionResistanceHorizontalHigh()
                        subviews.append(unreadBadge)
                    }

                    let contentRow = UIStackView(arrangedSubviews: subviews)
                    contentRow.alignment = .center
                    cell.contentView.addSubview(contentRow)

                    contentRow.setContentHuggingHigh()
                    contentRow.autoPinEdgesToSuperviewMargins()
                    contentRow.autoSetDimension(.height, toSize: OWSTableItem.iconSize, relation: .greaterThanOrEqual)

                    cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "payments")
                    cell.accessoryType = .disclosureIndicator

                    return cell
                },
                actionBlock: { [weak self] in
                    let vc = PaymentsSettingsViewController(mode: .inAppSettings)
                    self?.showSettingsViewController(vc)
                },
            ))
            contents.add(paymentsSection)
        }

        let section3 = OWSTableSection()
        section3.add(.disclosureItem(
            icon: .settingsHelp,
            withText: CommonStrings.help,
            actionBlock: { [weak self] in
                let vc = HelpViewController()
                self?.showSettingsViewController(vc)
            },
        ))
        section3.add(.item(
            icon: .settingsInvite,
            name: OWSLocalizedString("SETTINGS_INVITE_TITLE", comment: "Settings table view cell label"),
            actionBlock: { [weak self] in
                self?.showInviteFlow()
            },
        ))
        contents.add(section3)

        if DebugFlags.internalSettings {
            let internalSection = OWSTableSection()
            internalSection.add(.disclosureItem(
                icon: .settingsAdvanced,
                withText: "Internal",
                actionBlock: { [weak self] in
                    let vc = InternalSettingsViewController()
                    self?.showSettingsViewController(vc)
                },
            ))
            contents.add(internalSection)
        }

#if targetEnvironment(macCatalyst)
        if detailNavigationController != nil {
            for section in contents.sections {
                section.hasBackground = false
                section.hasSeparators = false
            }
        }
#endif

        self.contents = contents
    }

    private func showInviteFlow() {
        let inviteFlow = InviteFlow(presentingViewController: self)
        inviteFlow.present(isAnimated: true, completion: nil)
    }

    private func profileCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let avatarImageView = profileCellAvatarImageView()
        let infoStack = profileCellProfileInfoStack()

        cell.contentView.addSubview(avatarImageView)
        cell.contentView.addSubview(infoStack)

        avatarImageView.autoPinLeadingToSuperviewMargin()
        avatarImageView.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        avatarImageView.autoVCenterInSuperview()

        avatarImageView.autoPinTrailing(toLeadingEdgeOf: infoStack, offset: 12)

        infoStack.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        infoStack.autoVCenterInSuperview()
        infoStack.autoPinTrailingToSuperviewMargin()

        if let usernameLinkButton = profileCellUsernameLinkButton() {
            usernameLinkButton.sizeToFit() // this is required
            cell.accessoryView = usernameLinkButton
        } else {
            cell.accessoryType = .disclosureIndicator
        }

        return cell
    }

    private func profileCellAvatarImageView() -> UIView {
#if targetEnvironment(macCatalyst)
        let avatarSizeClass: ConversationAvatarView.Configuration.SizeClass = .fortyFour
#else
        let avatarSizeClass: ConversationAvatarView.Configuration.SizeClass = .customDiameter(72)
#endif
        let avatarImageView = ConversationAvatarView(
            sizeClass: avatarSizeClass,
            localUserDisplayMode: .asUser,
        )

        if let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress {
            avatarImageView.updateWithSneakyTransactionIfNecessary { config in
                config.dataSource = .address(localAddress)
            }
        }

        return avatarImageView
    }

    /// A view presenting quick info about the user's profile.
    private func profileCellProfileInfoStack() -> UIView {
        let profileInfoStack = UIStackView()
        profileInfoStack.axis = .vertical
        profileInfoStack.spacing = 0

        let nameLabel = UILabel()
        profileInfoStack.addArrangedSubview(nameLabel)
#if targetEnvironment(macCatalyst)
        nameLabel.font = UIFont.dynamicTypeBodyClamped.semibold()
#else
        nameLabel.font = UIFont.dynamicTypeTitle2Clamped.medium()
#endif
        if let fullName = localUserProfile?.filteredFullName?.nilIfEmpty {
            nameLabel.text = fullName
            nameLabel.textColor = Theme.primaryTextColor
        } else {
            nameLabel.text = OWSLocalizedString(
                "APP_SETTINGS_EDIT_PROFILE_NAME_PROMPT",
                comment: "Text prompting user to edit their profile name.",
            )
            nameLabel.textColor = Theme.accentBlueColor
        }

        @discardableResult
        func addSubtitleLabel(
            text: String,
            textColor: UIColor,
        ) -> UIView? {
            guard !text.isEmpty else { return nil }

            let label = UILabel()
            label.font = .dynamicTypeFootnoteClamped
            label.text = text
            label.textColor = textColor

            let containerView = UIView()
            containerView.layoutMargins = UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
            containerView.addSubview(label)
            label.autoPinEdgesToSuperviewMargins()

            profileInfoStack.addArrangedSubview(containerView)
            return containerView
        }

        if let phoneNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber {
            addSubtitleLabel(
                text: PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(phoneNumber),
                textColor: Theme.primaryTextColor,
            )
        } else {
            owsFailDebug("Missing local number")
        }

#if !targetEnvironment(macCatalyst)
        if let localUsernameState {
            switch localUsernameState {
            case let .available(username, _):
                addSubtitleLabel(
                    text: username,
                    textColor: Theme.primaryTextColor,
                )
            case .unset, .usernameAndLinkCorrupted, .linkCorrupted:
                break
            }
        }

        if let bioText = localUserProfile?.bioForDisplay {
            let bioLabel = addSubtitleLabel(
                text: bioText,
                textColor: Theme.secondaryTextAndIconColor,
            )
            bioLabel?.layoutMargins.top = 8
        }
#endif

        profileInfoStack.arrangedSubviews.last?.layoutMargins.bottom = 2

        return profileInfoStack
    }

    /// If we have a username, produces a button that takes the user to their username link QR code.
    private func profileCellUsernameLinkButton() -> UIButton? {
        let localUsername: String
        let localUsernameLink: Usernames.UsernameLink

        switch localUsernameState {
        case nil, .unset, .usernameAndLinkCorrupted, .linkCorrupted:
            return nil
        case let .available(username, usernameLink):
            localUsername = username
            localUsernameLink = usernameLink
        }

        var buttonConfiguration = UIButton.Configuration.roundGray(image: .qrCode)
        buttonConfiguration.contentInsets = .init(margin: 8) // makes 40 dp button
        return UIButton(
            configuration: buttonConfiguration,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }

                let usernameLinkController = UsernameLinkQRCodeContentController(
                    db: DependenciesBridge.shared.db,
                    localUsernameManager: DependenciesBridge.shared.localUsernameManager,
                    username: localUsername,
                    usernameLink: localUsernameLink,
                    changeDelegate: self,
                    scanDelegate: self,
                )

                let navController = OWSNavigationController(rootViewController: usernameLinkController)
                self.present(navController, animated: true)
            },
        )
    }

    private func didTapDonate() {
        showSettingsViewController(DonationSettingsViewController())
    }
}

extension AppSettingsViewController: UsernameChangeDelegate {
    func usernameStateDidChange(newState: Usernames.LocalUsernameState) {
        localUsernameState = newState
        updateTableContents()
    }
}

extension AppSettingsViewController: UsernameLinkScanDelegate {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink) {
        guard let presentingViewController else {
            owsFailDebug("Missing presenting view controller!")
            return
        }

        presentingViewController.dismiss(animated: true) {
            Task {
                guard
                    let (_, aci) = await UsernameQuerier().queryForUsernameLink(
                        link: usernameLink,
                        fromViewController: presentingViewController,
                    )
                else {
                    return
                }

                SignalApp.shared.presentConversationForAddress(
                    SignalServiceAddress(aci),
                    animated: true,
                )
            }
        }
    }
}

#if targetEnvironment(macCatalyst)
final class AppSettingsSplitViewController: UISplitViewController {

    let detailNavigationController: OWSNavigationController
    private let appSettingsViewController: AppSettingsViewController

    init(
        appSettingsViewController: AppSettingsViewController,
        detailNavigationController: OWSNavigationController = OWSNavigationController(),
        detailViewControllers: [UIViewController] = [],
    ) {
        self.appSettingsViewController = appSettingsViewController
        self.detailNavigationController = detailNavigationController

        super.init(style: .doubleColumn)

        let showsDefaultDetail = detailViewControllers.isEmpty
        appSettingsViewController.configureForSplitView(
            detailNavigationController: detailNavigationController,
            selectsProfileInitially: showsDefaultDetail,
        )

        let sidebarNavigationController = OWSNavigationController(rootViewController: appSettingsViewController)
        let initialDetailViewControllers = if showsDefaultDetail {
            [appSettingsViewController.makeProfileSettingsViewController()]
        } else {
            detailViewControllers
        }
        detailNavigationController.setViewControllers(initialDetailViewControllers, animated: false)

        setViewController(sidebarNavigationController, for: .primary)
        setViewController(detailNavigationController, for: .secondary)

        preferredSplitBehavior = .tile
        preferredDisplayMode = .oneBesideSecondary
        primaryBackgroundStyle = .sidebar
        presentsWithGesture = false
        displayModeButtonVisibility = .never

        minimumPrimaryColumnWidth = 240
        maximumPrimaryColumnWidth = 300
        preferredPrimaryColumnWidth = 270

        modalPresentationStyle = .formSheet
        preferredContentSize = CGSize(width: 920, height: 680)
        title = CommonStrings.openAppSettingsButton
    }

    func prepareForStandaloneWindow() {
        appSettingsViewController.prepareForStandaloneWindow()
    }

    @objc
    func showAppSettings() {
        AppEnvironment.shared.windowManagerRef.showSettingsWindow(
            self,
            replaceExistingContent: false,
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
