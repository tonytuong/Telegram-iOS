import Foundation
#if os(macOS)
    import PostboxMac
    import SwiftSignalKitMac
    import MtProtoKitMac
#else
    import Postbox
    import SwiftSignalKit
    #if BUCK
        import MtProtoKit
    #else
        import MtProtoKitDynamic
    #endif
#endif
import TelegramApi

public func removePeerMember(account: Account, peerId: PeerId, memberId: PeerId) -> Signal<Void, NoError> {
    if peerId.namespace == Namespaces.Peer.CloudChannel {
        return updateChannelMemberBannedRights(account: account, peerId: peerId, memberId: memberId, rights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: 0))
        |> mapToSignal { _ -> Signal<Void, NoError> in
            return .complete()
        }
    }
    
    return account.postbox.transaction { transaction -> Signal<Void, NoError> in
        if let peer = transaction.getPeer(peerId), let memberPeer = transaction.getPeer(memberId), let inputUser = apiInputUser(memberPeer) {
            if let group = peer as? TelegramGroup {
                return account.network.request(Api.functions.messages.deleteChatUser(chatId: group.id.id, userId: inputUser))
                |> mapError { error -> Void in
                    return Void()
                }
                |> `catch` { _ -> Signal<Api.Updates, NoError> in
                    return .complete()
                }
                |> mapToSignal { result -> Signal<Void, NoError> in
                    account.stateManager.addUpdates(result)
                    
                    return account.postbox.transaction { transaction -> Void in
                        transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
                            if let cachedData = cachedData as? CachedGroupData, let participants = cachedData.participants {
                                var updatedParticipants = participants.participants
                                for i in 0 ..< participants.participants.count {
                                    if participants.participants[i].peerId == memberId {
                                        updatedParticipants.remove(at: i)
                                        break
                                    }
                                }
                                
                                return cachedData.withUpdatedParticipants(CachedGroupParticipants(participants: updatedParticipants, version: participants.version))
                            } else {
                                return cachedData
                            }
                        })
                    }
                }
            } else {
                return .complete()
            }
        } else {
            return .complete()
        }
    } |> switchToLatest
}
