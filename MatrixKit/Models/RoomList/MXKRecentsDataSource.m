/*
 Copyright 2015 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXKRecentsDataSource.h"

#import "MXKRecentTableViewCell.h"

#import "NSBundle+MatrixKit.h"

@interface MXKRecentsDataSource ()
{
    /**
     Array of `MXSession` instances.
     */
    NSMutableArray *mxSessionArray;
    
    /**
     Array of `MXKSessionRecentsDataSource` instances (one by matrix session).
     */
    NSMutableArray *recentsDataSourceArray;
    
    /**
     The current search pattern list
     */
    NSArray* searchPatternsList;
}

@end

@implementation MXKRecentsDataSource

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        mxSessionArray = [NSMutableArray array];
        recentsDataSourceArray = [NSMutableArray array];
        
        readyRecentsDataSourceArray = [NSMutableArray array];
        shrinkedRecentsDataSourceArray = [NSMutableArray array];
        
        // Set default data and view classes
        [self registerCellDataClass:MXKRecentCellData.class forCellIdentifier:kMXKRecentCellIdentifier];
        [self registerCellViewClass:MXKRecentTableViewCell.class forCellIdentifier:kMXKRecentCellIdentifier];
    }
    return self;
}

- (instancetype)initWithMatrixSession:(MXSession *)matrixSession
{
    self = [self init];
    if (self)
    {
        [self addMatrixSession:matrixSession];
    }
    return self;
}


- (void)addMatrixSession:(MXSession *)matrixSession
{
    MXKSessionRecentsDataSource *recentsDataSource = [[MXKSessionRecentsDataSource alloc] initWithMatrixSession:matrixSession];
    
    if (recentsDataSource)
    {
        // Set the actual data and view classes
        [self registerCellDataClass:[self cellDataClassForCellIdentifier:kMXKRecentCellIdentifier] forCellIdentifier:kMXKRecentCellIdentifier];
        [self registerCellViewClass:[self cellViewClassForCellIdentifier:kMXKRecentCellIdentifier] forCellIdentifier:kMXKRecentCellIdentifier];
        
        [mxSessionArray addObject:matrixSession];
        
        recentsDataSource.delegate = self;
        [recentsDataSourceArray addObject:recentsDataSource];
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(dataSource:didAddMatrixSession:)])
        {
            [self.delegate dataSource:self didAddMatrixSession:matrixSession];
        }
        
        // Check the current state of the data source
        [self dataSource:recentsDataSource didStateChange:recentsDataSource.state];
    }
}

- (void)removeMatrixSession:(MXSession*)matrixSession
{
    for (NSUInteger index = 0; index < mxSessionArray.count; index++)
    {
        MXSession *mxSession = [mxSessionArray objectAtIndex:index];
        if (mxSession == matrixSession)
        {
            MXKSessionRecentsDataSource *recentsDataSource = [recentsDataSourceArray objectAtIndex:index];
            [recentsDataSource destroy];
            
            [readyRecentsDataSourceArray removeObject:recentsDataSource];
            
            [recentsDataSourceArray removeObjectAtIndex:index];
            [mxSessionArray removeObjectAtIndex:index];
            
            // Loop on 'didCellChange' method to let inherited 'MXKRecentsDataSource' class handle this removed data source.
            [self dataSource:recentsDataSource didCellChange:nil];
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(dataSource:didRemoveMatrixSession:)])
            {
                [self.delegate dataSource:self didRemoveMatrixSession:matrixSession];
            }
            
            break;
        }
    }
}

#pragma mark - MXKDataSource overridden

- (MXSession*)mxSession
{
    if (mxSessionArray.count > 1)
    {
        NSLog(@"[MXKRecentsDataSource] CAUTION: mxSession property is not relevant in case of multi-sessions (%tu)", mxSessionArray.count);
    }
    
    // TODO: This property is not well adapted in case of multi-sessions
    // We consider by default the first added session as the main one...
    if (mxSessionArray.count)
    {
        return [mxSessionArray firstObject];
    }
    return nil;
}

- (MXKDataSourceState)state
{
    // Manage a global state based on the state of each internal data source.
    
    MXKDataSourceState currentState = MXKDataSourceStateUnknown;
    MXKSessionRecentsDataSource *dataSource;
    
    if (recentsDataSourceArray.count)
    { 
        dataSource = [recentsDataSourceArray firstObject];
        currentState = dataSource.state;
        
        // Deduce the current state according to the internal data sources
        for (NSUInteger index = 1; index < recentsDataSourceArray.count; index++)
        {
            dataSource = [recentsDataSourceArray objectAtIndex:index];
            
            switch (dataSource.state)
            {
                case MXKDataSourceStateUnknown:
                    break;
                case MXKDataSourceStatePreparing:
                    currentState = MXKDataSourceStatePreparing;
                    break;
                case MXKDataSourceStateFailed:
                    if (currentState == MXKDataSourceStateUnknown)
                    {
                        currentState = MXKDataSourceStateFailed;
                    }
                    break;
                case MXKDataSourceStateReady:
                    if (currentState == MXKDataSourceStateUnknown || currentState == MXKDataSourceStateFailed)
                    {
                        currentState = MXKDataSourceStateReady;
                    }
                    break;
                    
                default:
                    break;
            }
        }
    }
    
    return currentState;
}

- (void)registerCellDataClass:(Class)cellDataClass forCellIdentifier:(NSString *)identifier
{
    [super registerCellDataClass:cellDataClass forCellIdentifier:identifier];
    
    for (MXKSessionRecentsDataSource *recentsDataSource in recentsDataSourceArray)
    {
        [recentsDataSource registerCellDataClass:cellDataClass forCellIdentifier:identifier];
    }
}

- (void)registerCellViewClass:(Class<MXKCellRendering>)cellViewClass forCellIdentifier:(NSString *)identifier
{
    [super registerCellViewClass:cellViewClass forCellIdentifier:identifier];
    
    for (MXKSessionRecentsDataSource *recentsDataSource in recentsDataSourceArray)
    {
        [recentsDataSource registerCellViewClass:cellViewClass forCellIdentifier:identifier];
    }
}

- (void)destroy
{
    for (MXKSessionRecentsDataSource *recentsDataSource in recentsDataSourceArray)
    {
        [recentsDataSource destroy];
    }
    readyRecentsDataSourceArray = nil;
    recentsDataSourceArray = nil;
    shrinkedRecentsDataSourceArray = nil;
    mxSessionArray = nil;
    
    searchPatternsList = nil;
    
    [super destroy];
}

#pragma mark -

- (NSArray*)mxSessions
{
    return [NSArray arrayWithArray:mxSessionArray];
}

- (NSUInteger)recentsDataSourcesCount
{
    return readyRecentsDataSourceArray.count;
}

- (NSUInteger)unreadCount
{
    NSUInteger unreadCount = 0;
    
    // Sum unreadCount of all ready data sources
    for (MXKSessionRecentsDataSource *recentsDataSource in readyRecentsDataSourceArray)
    {
        unreadCount += recentsDataSource.unreadCount;
    }
    return unreadCount;
}

- (void)markAllAsRead
{
    for (MXKSessionRecentsDataSource *recentsDataSource in readyRecentsDataSourceArray)
    {
        [recentsDataSource markAllAsRead];
    }
}

- (void)searchWithPatterns:(NSArray*)patternsList
{
    searchPatternsList = patternsList;
    
    for (MXKSessionRecentsDataSource *recentsDataSource in readyRecentsDataSourceArray)
    {
        [recentsDataSource searchWithPatterns:patternsList];
    }
}

- (UIView *)viewForHeaderInSection:(NSInteger)section withFrame:(CGRect)frame
{
    UIView *sectionHeader = nil;
    
    if (readyRecentsDataSourceArray.count > 1 && section < readyRecentsDataSourceArray.count)
    {
        MXKSessionRecentsDataSource *recentsDataSource = [readyRecentsDataSourceArray objectAtIndex:section];
        
        NSString* sectionTitle = recentsDataSource.mxSession.myUser.userId;
        
        if (recentsDataSource.unreadCount)
        {
            sectionTitle = [NSString stringWithFormat:@"%@ (%tu)", sectionTitle, recentsDataSource.unreadCount];
        }
        
        sectionHeader = [[UIView alloc] initWithFrame:frame];
        sectionHeader.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
        
        // Add shrink button
        UIButton *shrinkButton = [UIButton buttonWithType:UIButtonTypeCustom];
        CGRect frame = sectionHeader.frame;
        frame.origin.x = frame.origin.y = 0;
        shrinkButton.frame = frame;
        shrinkButton.backgroundColor = [UIColor clearColor];
        [shrinkButton addTarget:self action:@selector(onButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        shrinkButton.tag = section;
        [sectionHeader addSubview:shrinkButton];
        sectionHeader.userInteractionEnabled = YES;
        
        // Add shrink icon
        UIImage *chevron;
        if ([shrinkedRecentsDataSourceArray indexOfObject:recentsDataSource] != NSNotFound)
        {
            chevron = [NSBundle mxk_imageFromMXKAssetsBundleWithName:@"disclosure"];
        }
        else
        {
            chevron = [NSBundle mxk_imageFromMXKAssetsBundleWithName:@"shrink"];
        }
        UIImageView *chevronView = [[UIImageView alloc] initWithImage:chevron];
        chevronView.contentMode = UIViewContentModeCenter;
        frame = chevronView.frame;
        frame.origin.x = sectionHeader.frame.size.width - frame.size.width - 8;
        frame.origin.y = (sectionHeader.frame.size.height - frame.size.height) / 2;
        chevronView.frame = frame;
        [sectionHeader addSubview:chevronView];
        chevronView.autoresizingMask = (UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin);
        
        // Add label
        frame = sectionHeader.frame;
        frame.origin.x = 5;
        frame.origin.y = 5;
        frame.size.width = chevronView.frame.origin.x - 10;
        frame.size.height -= 10;
        UILabel *headerLabel = [[UILabel alloc] initWithFrame:frame];
        headerLabel.font = [UIFont boldSystemFontOfSize:16];
        headerLabel.backgroundColor = [UIColor clearColor];
        headerLabel.text = sectionTitle;
        [sectionHeader addSubview:headerLabel];
    }
    
    return sectionHeader;
}

- (id<MXKRecentCellDataStoring>)cellDataAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section < readyRecentsDataSourceArray.count)
    {
        MXKSessionRecentsDataSource *recentsDataSource = [readyRecentsDataSourceArray objectAtIndex:indexPath.section];
        
        return [recentsDataSource cellDataAtIndex:indexPath.row];
    }
    return nil;
}

- (CGFloat)cellHeightAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section < readyRecentsDataSourceArray.count)
    {
        MXKSessionRecentsDataSource *recentsDataSource = [readyRecentsDataSourceArray objectAtIndex:indexPath.section];
        
        return [recentsDataSource cellHeightAtIndex:indexPath.row];
    }
    return 0;
}

- (NSIndexPath*)cellIndexPathWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)matrixSession
{
    NSIndexPath *indexPath = nil;
    
    // Look for the right data source
    for (NSInteger section = 0; section < readyRecentsDataSourceArray.count; section++)
    {
        MXKSessionRecentsDataSource *recentsDataSource = readyRecentsDataSourceArray[section];
        if (recentsDataSource.mxSession == matrixSession)
        {
            // Check whether the source is not shrinked
            if ([shrinkedRecentsDataSourceArray indexOfObject:recentsDataSource] == NSNotFound)
            {
                // Look for the cell
                for (NSInteger index = 0; index < recentsDataSource.numberOfCells; index ++)
                {
                    id<MXKRecentCellDataStoring> recentCellData = [recentsDataSource cellDataAtIndex:index];
                    if ([roomId isEqualToString:recentCellData.roomDataSource.roomId])
                    {
                        // Got it
                        indexPath = [NSIndexPath indexPathForRow:index inSection:section];
                        break;
                    }
                }
            }
            break;
        }
    }
    
    return indexPath;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Check whether all data sources are ready before rendering recents
    if (self.state == MXKDataSourceStateReady)
    {
        return readyRecentsDataSourceArray.count;
    }
    return 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section < readyRecentsDataSourceArray.count)
    {
        MXKSessionRecentsDataSource *recentsDataSource = [readyRecentsDataSourceArray objectAtIndex:section];
        
        // Check whether the source is shrinked
        if ([shrinkedRecentsDataSourceArray indexOfObject:recentsDataSource] == NSNotFound)
        {
            return recentsDataSource.numberOfCells;
        }
    }
    
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section < readyRecentsDataSourceArray.count)
    {
        MXKSessionRecentsDataSource *recentsDataSource = [readyRecentsDataSourceArray objectAtIndex:indexPath.section];
        
        id<MXKRecentCellDataStoring> roomData = [recentsDataSource cellDataAtIndex:indexPath.row];
        
        MXKRecentTableViewCell *cell  = [tableView dequeueReusableCellWithIdentifier:kMXKRecentCellIdentifier forIndexPath:indexPath];
        
        // Make the bubble display the data
        [cell render:roomData];
        
        return cell;
    }
    return nil;
}

#pragma mark - MXKDataSourceDelegate

- (void)dataSource:(MXKDataSource*)dataSource didCellChange:(id)changes
{
    // Keep update readyRecentsDataSourceArray by checking number of cells
    if (dataSource.state == MXKDataSourceStateReady)
    {
        MXKSessionRecentsDataSource *recentsDataSource = (MXKSessionRecentsDataSource*)dataSource;
        
        if (recentsDataSource.numberOfCells)
        {
            // Check whether the data source must be added
            if ([readyRecentsDataSourceArray indexOfObject:recentsDataSource] == NSNotFound)
            {
                // Add this data source first
                [self dataSource:dataSource didStateChange:dataSource.state];
                return;
            }
        }
        else
        {
            // Check whether this data source must be removed
            if ([readyRecentsDataSourceArray indexOfObject:recentsDataSource] != NSNotFound)
            {
                [readyRecentsDataSourceArray removeObject:recentsDataSource];
                
                // Loop on 'didCellChange' method to let inherited 'MXKRecentsDataSource' class handle this removed data source.
                [self dataSource:recentsDataSource didCellChange:nil];
                return;
            }
        }
    }
    
    // Notify delegate
    [self.delegate dataSource:self didCellChange:changes];
}

- (void)dataSource:(MXKDataSource*)dataSource didStateChange:(MXKDataSourceState)state
{
    // Update list of ready data sources
    MXKSessionRecentsDataSource *recentsDataSource = (MXKSessionRecentsDataSource*)dataSource;
    if (dataSource.state == MXKDataSourceStateReady && recentsDataSource.numberOfCells)
    {
        if ([readyRecentsDataSourceArray indexOfObject:recentsDataSource] == NSNotFound)
        {
            [readyRecentsDataSourceArray addObject:recentsDataSource];
            
            // Check whether a search session is in progress
            if (searchPatternsList)
            {
                [recentsDataSource searchWithPatterns:searchPatternsList];
            }
            else
            {
                // Loop on 'didCellChange' method to let inherited 'MXKRecentsDataSource' class handle this new added data source.
                [self dataSource:recentsDataSource didCellChange:nil];
            }
        }
    }
    else if ([readyRecentsDataSourceArray indexOfObject:recentsDataSource] != NSNotFound)
    {
        [readyRecentsDataSourceArray removeObject:recentsDataSource];
        
        // Loop on 'didCellChange' method to let inherited 'MXKRecentsDataSource' class handle this removed data source.
        [self dataSource:recentsDataSource didCellChange:nil];
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(dataSource:didStateChange:)])
    {
        [self.delegate dataSource:self didStateChange:self.state];
    }
}

#pragma mark - Action

- (IBAction)onButtonPressed:(id)sender
{
    if ([sender isKindOfClass:[UIButton class]])
    {
        UIButton *shrinkButton = (UIButton*)sender;
        
        if (shrinkButton.tag < readyRecentsDataSourceArray.count)
        {
            MXKSessionRecentsDataSource *recentsDataSource = [readyRecentsDataSourceArray objectAtIndex:shrinkButton.tag];
            
            NSUInteger index = [shrinkedRecentsDataSourceArray indexOfObject:recentsDataSource];
            if (index != NSNotFound)
            {
                // Disclose the
                [shrinkedRecentsDataSourceArray removeObjectAtIndex:index];
            }
            else
            {
                // Shrink the recents from this session
                [shrinkedRecentsDataSourceArray addObject:recentsDataSource];
            }
            
            // Loop on 'didCellChange' method to let inherited 'MXKRecentsDataSource' class handle change on this data source.
            [self dataSource:recentsDataSource didCellChange:nil];
        }
    }
}

@end
