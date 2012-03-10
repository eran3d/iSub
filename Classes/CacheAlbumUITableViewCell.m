//
//  AlbumUITableViewCell.m
//  iSub
//
//  Created by Ben Baron on 3/20/10.
//  Copyright 2010 Ben Baron. All rights reserved.
//

#import "CacheAlbumUITableViewCell.h"
#import "ViewObjectsSingleton.h"
#import "DatabaseSingleton.h"
#import "FMDatabaseAdditions.h"

#import "CellOverlay.h"
#import "Song.h"
#import "NSNotificationCenter+MainThread.h"
#import "CacheSingleton.h"
#import "ISMSCacheQueueManager.h"

@implementation CacheAlbumUITableViewCell

@synthesize segments, coverArtView, albumNameScrollView, albumNameLabel;

#pragma mark - Overlay

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier 
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) 
	{	
		coverArtView = [[UIImageView alloc] init];
		[self.contentView addSubview:coverArtView];
		[coverArtView release];
		
		albumNameScrollView = [[UIScrollView alloc] init];
		albumNameScrollView.frame = CGRectMake(65, 0, 250, 60);
		albumNameScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		albumNameScrollView.showsVerticalScrollIndicator = NO;
		albumNameScrollView.showsHorizontalScrollIndicator = NO;
		albumNameScrollView.userInteractionEnabled = NO;
		albumNameScrollView.decelerationRate = UIScrollViewDecelerationRateFast;
		[self.contentView addSubview:albumNameScrollView];
		[albumNameScrollView release];
		
		albumNameLabel = [[UILabel alloc] init];
		albumNameLabel.backgroundColor = [UIColor clearColor];
		albumNameLabel.textAlignment = UITextAlignmentLeft; // default
		albumNameLabel.font = [UIFont boldSystemFontOfSize:20];
		[albumNameScrollView addSubview:albumNameLabel];
		[albumNameLabel release];
	}
	
	return self;
}

- (void)layoutSubviews 
{
    [super layoutSubviews];

	// Automatically set the width based on the width of the text
	albumNameLabel.frame = CGRectMake(0, 0, 230, 60);
	CGSize expectedLabelSize = [albumNameLabel.text sizeWithFont:albumNameLabel.font constrainedToSize:CGSizeMake(1000,60) lineBreakMode:albumNameLabel.lineBreakMode]; 
	CGRect newFrame = albumNameLabel.frame;
	newFrame.size.width = expectedLabelSize.width;
	albumNameLabel.frame = newFrame;
	
	coverArtView.frame = CGRectMake(0, 0, 60, 60);
}

- (void)dealloc 
{
	[segments release]; segments = nil;
	//[seg1 release]; seg1 = nil;

    [super dealloc];
}

#pragma mark - Overlay

- (void)showOverlay
{
	[super showOverlay];
	
	if (self.isOverlayShowing)
	{
		[self.overlayView.downloadButton setImage:[UIImage imageNamed:@"delete-button.png"] forState:UIControlStateNormal];
		[self.overlayView.downloadButton addTarget:self action:@selector(deleteAction) forControlEvents:UIControlEventTouchUpInside];
	}
}

- (void)deleteAction
{
	[viewObjectsS showLoadingScreenOnMainWindowWithMessage:@"Deleting"];
	[self performSelector:@selector(deleteAllSongs) withObject:nil afterDelay:0.05];
	
	self.overlayView.downloadButton.alpha = .3;
	self.overlayView.downloadButton.enabled = NO;
	
	[self hideOverlay];
}

- (void)deleteAllSongs
{
	NSMutableArray *newSegments = [NSMutableArray arrayWithArray:segments];
	[newSegments addObject:self.albumNameLabel.text];
	
	NSUInteger segment = [newSegments count];

	NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT md5 FROM cachedSongsLayout WHERE seg1 = ? ", segment+1];
	for (int i = 2; i <= segment; i++)
	{
		[query appendFormat:@" AND seg%i = ? ", i];
	}
	[query appendFormat:@"ORDER BY seg%i COLLATE NOCASE", segment+1, segment+1];
	
	FMResultSet *result = [databaseS.songCacheDb executeQuery:query withArgumentsInArray:newSegments];
	
	while ([result next])
	{
		if ([result stringForColumnIndex:0] != nil)
			[Song removeSongFromCacheDbByMD5:[NSString stringWithString:[result stringForColumnIndex:0]]];
	}
	[result close];
	
	[cacheS findCacheSize];
		
	// Reload the cached songs table
	[NSNotificationCenter postNotificationToMainThreadWithName:@"cachedSongDeleted"];
	
	if (!cacheQueueManagerS.isQueueDownloading)
		[cacheQueueManagerS startDownloadQueue];
	
	// Hide the loading screen
	[viewObjectsS hideLoadingScreen];
}

- (void)queueAction
{
	[viewObjectsS showLoadingScreenOnMainWindowWithMessage:nil];
	[self performSelector:@selector(queueAllSongs) withObject:nil afterDelay:0.05];
	[self hideOverlay];
}

- (void)queueAllSongs
{
	NSMutableArray *newSegments = [NSMutableArray arrayWithArray:segments];
	[newSegments addObject:self.albumNameLabel.text];
	
	NSUInteger segment = [newSegments count];
	
	NSMutableString *query = [NSMutableString stringWithFormat:@"SELECT md5 FROM cachedSongsLayout WHERE seg1 = ? ", segment+1];
	for (int i = 2; i <= segment; i++)
	{
		[query appendFormat:@" AND seg%i = ? ", i];
	}
	[query appendFormat:@"ORDER BY seg%i COLLATE NOCASE", segment+1, segment+1];
	
	FMResultSet *result = [databaseS.songCacheDb executeQuery:query withArgumentsInArray:newSegments];
	
	while ([result next])
	{
		if ([result stringForColumnIndex:0] != nil)
			[[Song songFromCacheDb:[NSString stringWithString:[result stringForColumnIndex:0]]] addToCurrentPlaylist];
	}
	[result close];
	
	// Hide the loading screen
	[viewObjectsS hideLoadingScreen];
}

#pragma mark - Scrolling

- (void)scrollLabels
{
	if (albumNameLabel.frame.size.width > albumNameScrollView.frame.size.width)
	{
		[UIView beginAnimations:@"scroll" context:nil];
		[UIView setAnimationDelegate:self];
		[UIView setAnimationDidStopSelector:@selector(textScrollingStopped)];
		[UIView setAnimationDuration:albumNameLabel.frame.size.width/150.];
		albumNameScrollView.contentOffset = CGPointMake(albumNameLabel.frame.size.width - albumNameScrollView.frame.size.width + 10, 0);
		[UIView commitAnimations];
	}
}

- (void)textScrollingStopped
{
	[UIView beginAnimations:@"scroll" context:nil];
	[UIView setAnimationDuration:albumNameLabel.frame.size.width/150.];
	albumNameScrollView.contentOffset = CGPointZero;
	[UIView commitAnimations];
}

@end
