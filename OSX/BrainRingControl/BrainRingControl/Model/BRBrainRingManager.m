//
//  BRBrainRingManager.m
//  BrainRingControl
//
//  Created by Sergey Dunets on 06.10.13.
//  Copyright (c) 2013 Sergey Dunets. All rights reserved.
//

#import "BRBrainRingManager.h"
#import <sys/time.h>

// Notifications
NSString * const kGameDidStop = @"kGameDidStop";
NSString * const kGameWillStartAfterDelay = @"kGameWillStartAfterDelay";
NSString * const kPlayerDidPressFalseStart = @"kPlayerDidPressFalseStart";
NSString * const kGameDidStartFullTime = @"kGameDidStart";
NSString * const kPlayerDidPressButton = @"kPlayerDidPressButton";
NSString * const kGameDidStartShortTime = @"kGameDidResumeAfterWrongAnswer";

// Notification Info keys
NSString * const kPlayersKey = @"kPlayersKey";
NSString * const kDelayKey = @"kDelayKey";
NSString * const kPlayerKey = @"kPlayerKey";
NSString * const kPlayerTimeKey = @"kPlayerTimeKey";

const NSUInteger kMaxPlayersCount = 2;

const NSTimeInterval kFullTime = 60.0;
const NSTimeInterval kShortTime = 20.0;


@interface BRBrainRingManager ()

/// @brief Current game state.
@property (nonatomic, assign) BRGameState       gameState;

/// @brief All players registered, count in range between 0 and kMaxPlayersCount.
@property (nonatomic, retain) NSMutableArray    *allPlayers;

/// @brief Players allowed to press the "Big Friendly Button".
@property (nonatomic, retain) NSMutableArray    *playersInGame;

/// @brief Main game timer.
@property (nonatomic, retain) NSTimer           *gameTimer;

/// @brief Removes a player from self.playersInGame.
- (void)disablePlayer:(NSString *)aPlayer;

/// @brief Schedules the game timer for a full time.
/// @return YES if timer was started successfully.
- (BOOL)startTimerForFullTime;

/// @brief Calls -startTimerForFullTime.
/// @param[in] aTimer NSTimer instance.
- (void)randomDelayTimerFired:(NSTimer *)aTimer;

/// @brief Calls -stopGame.
/// @param[in] aTimer NSTimer instance.
- (void)gameTimerFired:(NSTimer *)aTimer;

@end


@implementation BRBrainRingManager

#pragma mark - Public

- (id)init
{
    if (self = [super init])
    {
        _allPlayers = [NSMutableArray new];
        _playersInGame = [NSMutableArray new];
        _gameState = kGameStateStopped;
    }
    
    return self;
}

- (void)dealloc
{
    [_gameTimer invalidate];
    [_gameTimer release];
    [_allPlayers release];
    [_playersInGame release];
    
    [super dealloc];
}


#pragma mark - Managing players

- (BOOL)addPlayer:(NSString *)aPlayer
{
    BOOL result = NO;
    NSMutableArray *players = self.allPlayers;
    if (kMaxPlayersCount < players.count && ![players containsObject:aPlayer])
    {
        [players addObject:aPlayer];
        result = YES;
    }
    
    return result;
}

- (void)removePlayer:(NSString *)aPlayer
{
    [self.allPlayers removeObject:aPlayer];
    [self.playersInGame removeObject:aPlayer];
}

- (void)disablePlayer:(NSString *)aPlayer
{
    [self.playersInGame removeObject:aPlayer];
}

#pragma mark - Gameplay

- (void)player:(NSString *)aPlayer didPressButtonWithInternalTime:(NSTimeInterval)aTime internalGameState:(BRGameState)aState
{
    assert([self.playersInGame containsObject:aPlayer]);
    if (![self.playersInGame containsObject:aPlayer])
    {
        return;
    }
    
    [self disablePlayer:aPlayer];
    [self.gameTimer invalidate];
    
    switch (aState)
    {
        case kGameStateStopped:
        case kGameStateDelayedBeforeTimerStart:
        {
            self.gameState = kGameStateFalseStart;
            [[NSNotificationCenter defaultCenter] postNotificationName:kPlayerDidPressFalseStart
                                                                object:self
                                                              userInfo:@{kPlayerKey:aPlayer, kPlayerTimeKey:@(aTime)}];
            break;
        }
        case kGameStateTimerCountsFullTime:
        case kGameStateTimerCountsShortTime:
        {
            self.gameState = kGameStatePaused;
            [[NSNotificationCenter defaultCenter] postNotificationName:kPlayerDidPressButton
                                                                object:self
                                                              userInfo:@{kPlayerKey:aPlayer, kPlayerTimeKey:@(aTime)}];
            break;
        }
        default:
        {
            return;
        }
    }
}

- (void)player:(NSString *)aPLayer didAnswerCorrecly:(BOOL)aFlag
{
    // Ensure, that the player is allowed to press the Big Friendly Button and
    // the game timer is not scheduled
    assert([self.playersInGame containsObject:aPLayer] && ![self.gameTimer isValid]);
    if (![self.playersInGame containsObject:aPLayer] || [self.gameTimer isValid])
    {
        return;
    }
    
    if (aFlag)
    {
        [self stopGame];
    }
    else
    {
        [self startTimerForShortTime];
    }
}

- (BOOL)startTimerForFullTimeAfterRandomDelay
{
    assert(![self.gameTimer isValid]);
    
    BOOL result = self.gameState == kGameStateStopped;
    
    if (result)
    {
        result = self.allPlayers.count == kMaxPlayersCount;
    }
    
    if (result)
    {
        // delay for 1-1.5 s
        NSTimeInterval randomDelay = 1.0 + arc4random_uniform(500.0) / 500.0;
        
        self.gameTimer = [NSTimer scheduledTimerWithTimeInterval:randomDelay
                                                          target:self
                                                        selector:@selector(randomDelayTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
        self.gameState = kGameStateDelayedBeforeTimerStart;
        [[NSNotificationCenter defaultCenter] postNotificationName:kGameWillStartAfterDelay
                                                            object:self
                                                          userInfo:@{kDelayKey:@(randomDelay)}];
    }
    
    return result;
}

- (BOOL)startTimerForShortTime
{
    assert(![self.gameTimer isValid]);
    
    BOOL result = self.gameState == kGameStatePaused || self.gameState == kGameStateFalseStart;
    
    if (result)
    {
        result = self.playersInGame.count == 1;
    }
    
    if (result)
    {
        self.gameTimer = [NSTimer scheduledTimerWithTimeInterval:kShortTime
                                                          target:self
                                                        selector:@selector(gameTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
        self.gameState = kGameStateTimerCountsShortTime;
        [[NSNotificationCenter defaultCenter] postNotificationName:kGameDidStartShortTime
                                                            object:self
                                                          userInfo:nil];
    }
    
    return result;
}

#pragma mark - Private

- (void)randomDelayTimerFired:(NSTimer *)aTimer
{
    if (aTimer == self.gameTimer)
    {
        assert(![self.gameTimer isValid]);
        
        self.gameTimer = nil;
        [self startTimerForFullTime];
    }
}

- (void)gameTimerFired:(NSTimer *)aTimer
{
    if (aTimer == self.gameTimer)
    {
        [self stopGame];
    }
}

- (BOOL)startTimerForFullTime
{
    assert(![self.gameTimer isValid]);
    
    BOOL result = self.gameState == kGameStateDelayedBeforeTimerStart;
    
    if (result)
    {
        result = self.allPlayers.count == kMaxPlayersCount;
    }
    
    if (result)
    {
        self.gameTimer = [NSTimer scheduledTimerWithTimeInterval:kFullTime
                                                          target:self
                                                        selector:@selector(gameTimerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
        self.gameState = kGameStateTimerCountsFullTime;
        [[NSNotificationCenter defaultCenter] postNotificationName:kGameDidStartFullTime
                                                            object:self
                                                          userInfo:nil];
    }
    
    return result;
}

- (void)stopGame
{
    [self.gameTimer invalidate];
    self.gameTimer = nil;
    self.gameState = kGameStateStopped;
    self.playersInGame = [[self.allPlayers mutableCopy] autorelease];
}


@end
