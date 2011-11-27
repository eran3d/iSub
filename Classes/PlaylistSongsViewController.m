//
//  PlaylistSongsViewController.m
//  iSub
//
//  Created by Ben Baron on 4/2/10.
//  Copyright 2010 Ben Baron. All rights reserved.
//

#import "PlaylistSongsViewController.h"
#import "iSubAppDelegate.h"
#import "ViewObjectsSingleton.h"
#import "MusicSingleton.h"
#import "DatabaseSingleton.h"
#import "iPhoneStreamingPlayerViewController.h"
#import "ServerListViewController.h"
#import "PlaylistSongUITableViewCell.h"
#import "AsynchronousImageViewCached.h"
#import "Song.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "NSString+md5.h"
#import "EGORefreshTableHeaderView.h"
#import "CustomUIAlertView.h"
#import "NSString+rfcEncode.h"
#import "TBXML.h"
#import "SavedSettings.h"
#import "NSMutableURLRequest+SUS.h"
#import "OrderedDictionary.h"
#import "SUSServerPlaylist.h"

@interface PlaylistSongsViewController (Private)

- (void)dataSourceDidFinishLoadingNewData;

@end


@implementation PlaylistSongsViewController

@synthesize md5, serverPlaylist;
@synthesize reloading=_reloading;


-(BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)inOrientation 
{
	
	if ([SavedSettings sharedInstance].isRotationLockEnabled && inOrientation != UIInterfaceOrientationPortrait)
		return NO;
	
    return YES;
}

- (void)viewDidLoad 
{
    [super viewDidLoad];
	appDelegate = (iSubAppDelegate *)[[UIApplication sharedApplication] delegate];
	viewObjects = [ViewObjectsSingleton sharedInstance];
	musicControls = [MusicSingleton sharedInstance];
	databaseControls = [DatabaseSingleton sharedInstance];

    if (viewObjects.isLocalPlaylist)
	{
		self.title = [databaseControls.localPlaylistsDb stringForQuery:@"SELECT playlist FROM localPlaylists WHERE md5 = ?", self.md5];
		
		UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 50)];
		headerView.backgroundColor = viewObjects.darkNormal;
		
		UIImageView *sendImage = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"upload-playlist.png"]];
		sendImage.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		sendImage.frame = CGRectMake(23, 11, 24, 24);
		[headerView addSubview:sendImage];
		[sendImage release];
		
		UILabel *sendLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 320, 50)];
		sendLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
		sendLabel.backgroundColor = [UIColor clearColor];
		sendLabel.textColor = [UIColor colorWithRed:186.0/255.0 green:191.0/255.0 blue:198.0/255.0 alpha:1];
		sendLabel.textAlignment = UITextAlignmentCenter;
		sendLabel.font = [UIFont boldSystemFontOfSize:30];
		sendLabel.text = @"Save to Server";
		[headerView addSubview:sendLabel];
		[sendLabel release];
		
		UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
		sendButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
		sendButton.frame = CGRectMake(0, 0, 320, 40);
		[sendButton addTarget:self action:@selector(uploadPlaylistAction:) forControlEvents:UIControlEventTouchUpInside];
		[headerView addSubview:sendButton];
		
		self.tableView.tableHeaderView = headerView;
		[headerView release];
		
		UIImageView *fadeTop = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"table-fade-top.png"]];
		fadeTop.frame =CGRectMake(0, -10, self.tableView.bounds.size.width, 10);
		fadeTop.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.tableView addSubview:fadeTop];
		[fadeTop release];
	}
	else
	{
        self.title = serverPlaylist.playlistName;
		playlistCount = [databaseControls.localPlaylistsDb intForQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM splaylist%@", md5]];
		[self.tableView reloadData];
		
		// Add the pull to refresh view
		refreshHeaderView = [[EGORefreshTableHeaderView alloc] initWithFrame:CGRectMake(0.0f, 0.0f - self.tableView.bounds.size.height, 320.0f, self.tableView.bounds.size.height)];
		refreshHeaderView.backgroundColor = [UIColor colorWithRed:226.0/255.0 green:231.0/255.0 blue:237.0/255.0 alpha:1.0];
		[self.tableView addSubview:refreshHeaderView];
		[refreshHeaderView release];
	}
	
	// Add the table fade
	UIImageView *fadeBottom = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"table-fade-bottom.png"]] autorelease];
	fadeBottom.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, 10);
	fadeBottom.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.tableView.tableFooterView = fadeBottom;
}

-(void)loadData
{
    NSDictionary *parameters = [NSDictionary dictionaryWithObject:n2N(serverPlaylist.playlistId) forKey:@"id"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithSUSAction:@"getPlaylist" andParameters:parameters];
	
	connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
	if (connection)
	{
		// Create the NSMutableData to hold the received data.
		// receivedData is an instance variable declared elsewhere.
		receivedData = [[NSMutableData data] retain];
		
		self.tableView.scrollEnabled = NO;
		[viewObjects showAlbumLoadingScreen:self.view sender:self];
	} 
	else 
	{
		// Inform the user that the connection failed.
		CustomUIAlertView *alert = [[CustomUIAlertView alloc] initWithTitle:@"Error" message:@"There was an error grabbing the playlist.\n\nCould not create the network request." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:NO];
		[alert release];
	}
}	

- (void)cancelLoad
{
	[connection cancel];
	self.tableView.scrollEnabled = YES;
	[viewObjects hideLoadingScreen];
	
	if (!viewObjects.isLocalPlaylist)
	{
		[self dataSourceDidFinishLoadingNewData];
	}
}

- (void)viewWillAppear:(BOOL)animated 
{
    [super viewWillAppear:animated];
	
	if(musicControls.showPlayerIcon)
	{
		self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"now-playing.png"] style:UIBarButtonItemStyleBordered target:self action:@selector(nowPlayingAction:)] autorelease];
	}
	else
	{
		self.navigationItem.rightBarButtonItem = nil;
	}
	
	if (viewObjects.isLocalPlaylist)
	{
		//appDelegate.listOfPlaylistSongs = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@%@List", appDelegate.defaultUrl, appDelegate.localPlaylist]]];
		//appDelegate.dictOfPlaylistSongs = [NSKeyedUnarchiver unarchiveObjectWithData:[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@%@Dict", appDelegate.defaultUrl, appDelegate.localPlaylist]]];
	}
	else
	{
		if (playlistCount == 0)
		{
			[self loadData];
		}
	}
}


- (void)didReceiveMemoryWarning 
{
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload {
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
}


- (void) settingsAction:(id)sender 
{
	ServerListViewController *serverListViewController = [[ServerListViewController alloc] initWithNibName:@"ServerListViewController" bundle:nil];
	serverListViewController.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:serverListViewController animated:YES];
	[serverListViewController release];
}


- (IBAction)nowPlayingAction:(id)sender
{
	iPhoneStreamingPlayerViewController *streamingPlayerViewController = [[iPhoneStreamingPlayerViewController alloc] initWithNibName:@"iPhoneStreamingPlayerViewController" bundle:nil];
	streamingPlayerViewController.hidesBottomBarWhenPushed = YES;
	[self.navigationController pushViewController:streamingPlayerViewController animated:YES];
	[streamingPlayerViewController release];  
}

- (void)uploadPlaylistAction:(id)sender
{	
    OrderedDictionary *parameters = [OrderedDictionary dictionaryWithObject:n2N(self.title) forKey:@"name"];
    
	NSString *query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM playlist%@", self.md5];
	NSUInteger count = [databaseControls.localPlaylistsDb intForQuery:query];
	for (int i = 1; i <= count; i++)
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		NSString *query = [NSString stringWithFormat:@"SELECT songId FROM playlist%@ WHERE ROWID = %i", self.md5, i];
		NSString *songId = [databaseControls.localPlaylistsDb stringForQuery:query];
		
        [parameters setObject:n2N(songId) forKey:@"songId"];
        
		[pool release];
	}
	
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithSUSAction:@"createPlaylist" andParameters:parameters];
	
	connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
	if (connection)
	{
		// Create the NSMutableData to hold the received data.
		// receivedData is an instance variable declared elsewhere.
		receivedData = [[NSMutableData data] retain];
		
		self.tableView.scrollEnabled = NO;
		[viewObjects showAlbumLoadingScreen:self.view sender:self];
	} 
	else 
	{
		// Inform the user that the connection failed.
		CustomUIAlertView *alert = [[CustomUIAlertView alloc] initWithTitle:@"Error" message:@"There was an error saving the playlist to the server.\n\nCould not create the network request." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:NO];
		[alert release];
	}
}

#pragma mark Connection Delegate

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)space 
{
	if([[space authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) 
		return YES; // Self-signed cert will be accepted
	
	return NO;
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{	
	if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
	{
		[challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge]; 
	}
	[challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	[receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)theConnection didReceiveData:(NSData *)incrementalData 
{
    [receivedData appendData:incrementalData];
}

- (void)connection:(NSURLConnection *)theConnection didFailWithError:(NSError *)error
{
	NSString *message = @"";
	if (viewObjects.isLocalPlaylist)
	{
		message = [NSString stringWithFormat:@"There was an error saving the playlist to the server.\n\nError %i: %@", 
											 [error code], 
											 [error localizedDescription]];
	}
	else
	{
		message = [NSString stringWithFormat:@"There was an error loading the playlist.\n\nError %i: %@", 
				   [error code], 
				   [error localizedDescription]];
	}
	
	// Inform the user that the connection failed.
	CustomUIAlertView *alert = [[CustomUIAlertView alloc] initWithTitle:@"Error" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:NO];
	[alert release];
	
	self.tableView.scrollEnabled = YES;
	[viewObjects hideLoadingScreen];
	
	[theConnection release];
	[receivedData release];
	
	[self dataSourceDidFinishLoadingNewData];
}	

- (void)connectionDidFinishLoading:(NSURLConnection *)theConnection 
{	
	if (!viewObjects.isLocalPlaylist)
	{
        // Parse the data
        //
		DLog(@"%@", [[[NSString alloc] initWithData:receivedData encoding:NSUTF8StringEncoding] autorelease]);
        TBXML *tbxml = [[TBXML alloc] initWithXMLData:receivedData];
        TBXMLElement *root = tbxml.rootXMLElement;
        if (root) 
        {
            TBXMLElement *error = [TBXML childElementNamed:@"error" parentElement:root];
            if (error)
            {
                // TODO: handle error
            }
            else
            {
                TBXMLElement *playlist = [TBXML childElementNamed:@"playlist" parentElement:root];
                if (playlist)
                {
                    [databaseControls removeServerPlaylistTable:md5];
                    [databaseControls createServerPlaylistTable:md5];
                    
                    TBXMLElement *entry = [TBXML childElementNamed:@"entry" parentElement:playlist];
                    while (entry != nil)
                    {
                        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                        
                        Song *aSong = [[Song alloc] initWithTBXMLElement:entry];
                        [aSong insertIntoServerPlaylistWithPlaylistId:md5];
                        [aSong release];
                        
                        // Get the next message
                        entry = [TBXML nextSiblingNamed:@"entry" searchFromElement:entry];
                        
                        [pool release];
                    }
                }
            }
        }
		[tbxml release];
		
		self.tableView.scrollEnabled = YES;

		playlistCount = [databaseControls.localPlaylistsDb intForQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM splaylist%@", md5]];
		[self.tableView reloadData];
		
		[self dataSourceDidFinishLoadingNewData];
		
		[receivedData release];
		[viewObjects hideLoadingScreen];
	}
	else
	{
		[self performSelectorInBackground:@selector(parseData) withObject:nil];
	}
	
	self.tableView.scrollEnabled = YES;
	[theConnection release];
}

static NSString *kName_Error = @"error";

- (void) subsonicErrorCode:(NSString *)errorCode message:(NSString *)message
{
	CustomUIAlertView *alert = [[CustomUIAlertView alloc] initWithTitle:@"Subsonic Error" message:message delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles: nil];
	alert.tag = 1;
	[alert show];
	[alert release];
	//DLog(@"Subsonic error %@:  %@", errorCode, message);
}

- (void)parseData
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// Parse the data
	//
	TBXML *tbxml = [[TBXML alloc] initWithXMLData:receivedData];
    TBXMLElement *root = tbxml.rootXMLElement;
    if (root) 
	{
		TBXMLElement *error = [TBXML childElementNamed:kName_Error parentElement:root];
		if (error)
		{
			NSString *code = [TBXML valueOfAttributeNamed:@"code" forElement:error];
			NSString *message = [TBXML valueOfAttributeNamed:@"message" forElement:error];
			[self subsonicErrorCode:code message:message];
		}
	}
    [tbxml release];
	
	[receivedData release];
	
	[viewObjects performSelectorOnMainThread:@selector(hideLoadingScreen) withObject:nil waitUntilDone:NO];
	
	[pool release];
}


#pragma mark Table view methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView 
{
    return 1;
}


// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section 
{
	if (viewObjects.isLocalPlaylist)
	{
		return [databaseControls.localPlaylistsDb intForQuery:[NSString stringWithFormat:@"SELECT COUNT(*) FROM playlist%@", self.md5]];
	}
	else
	{
		return playlistCount;
		//return [viewObjects.listOfPlaylistSongs count];
	}
}


// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
	PlaylistSongUITableViewCell *cell = [[[PlaylistSongUITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
	cell.indexPath = indexPath;
	cell.playlistMD5 = self.md5;
	
	// Set up the cell...
	Song *aSong;
	if (viewObjects.isLocalPlaylist)
	{
		aSong = [Song songFromDbRow:indexPath.row inTable:[NSString stringWithFormat:@"playlist%@", self.md5] inDatabase:databaseControls.localPlaylistsDb];
		//DLog(@"aSong: %@", aSong);
	}
	else
	{
		//aSong = [viewObjects.listOfPlaylistSongs objectAtIndex:indexPath.row];
		aSong = [Song songFromServerPlaylistId:md5 row:indexPath.row];
	}
	
	[cell.coverArtView loadImageFromCoverArtId:aSong.coverArtId];
	
	cell.backgroundView = [[[UIView alloc] init] autorelease];
	if(indexPath.row % 2 == 0)
	{
		if ([databaseControls.songCacheDb stringForQuery:@"SELECT md5 FROM cachedSongs WHERE md5 = ? and finished = 'YES'", [aSong.path md5]] != nil)
			cell.backgroundView.backgroundColor = [viewObjects currentLightColor];
		else
			cell.backgroundView.backgroundColor = viewObjects.lightNormal;
	}
	else
	{
		if ([databaseControls.songCacheDb stringForQuery:@"SELECT md5 FROM cachedSongs WHERE md5 = ? and finished = 'YES'", [aSong.path md5]] != nil)
			cell.backgroundView.backgroundColor = [viewObjects currentDarkColor];
		else
			cell.backgroundView.backgroundColor = viewObjects.darkNormal;
	}
	
	[cell.numberLabel setText:[NSString stringWithFormat:@"%i", (indexPath.row + 1)]];
	[cell.songNameLabel setText:aSong.title];
	if (aSong.album)
		[cell.artistNameLabel setText:[NSString stringWithFormat:@"%@ - %@", aSong.artist, aSong.album]];
	else
		[cell.artistNameLabel setText:aSong.artist];
	
	return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath 
{
	if (viewObjects.isCellEnabled)
	{		
		// Clear the current playlist
		if ([SavedSettings sharedInstance].isJukeboxEnabled)
			[databaseControls resetJukeboxPlaylist];
		else
			[databaseControls resetCurrentPlaylistDb];
		
		if (viewObjects.isLocalPlaylist)
		{			
			[databaseControls.localPlaylistsDb executeUpdate:@"ATTACH DATABASE ? AS ?", [NSString stringWithFormat:@"%@/%@currentPlaylist.db", databaseControls.databaseFolderPath, [[SavedSettings sharedInstance].urlString md5]], @"currentPlaylistDb"];
			if ([databaseControls.localPlaylistsDb hadError]) { DLog(@"Err attaching the localPlaylistsDb %d: %@", [databaseControls.localPlaylistsDb lastErrorCode], [databaseControls.localPlaylistsDb lastErrorMessage]); }
			if ([SavedSettings sharedInstance].isJukeboxEnabled)
				[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"INSERT INTO jukeboxCurrentPlaylist SELECT * FROM playlist%@", self.md5]];
			else
				[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"INSERT INTO currentPlaylist SELECT * FROM playlist%@", self.md5]];
			[databaseControls.localPlaylistsDb executeUpdate:@"DETACH DATABASE currentPlaylistDb"];
		}
		else
		{
			[databaseControls.localPlaylistsDb executeUpdate:@"ATTACH DATABASE ? AS ?", [NSString stringWithFormat:@"%@/%@currentPlaylist.db", databaseControls.databaseFolderPath, [[SavedSettings sharedInstance].urlString md5]], @"currentPlaylistDb"];
			if ([databaseControls.localPlaylistsDb hadError]) { DLog(@"Err attaching the localPlaylistsDb %d: %@", [databaseControls.localPlaylistsDb lastErrorCode], [databaseControls.localPlaylistsDb lastErrorMessage]); }
			if ([SavedSettings sharedInstance].isJukeboxEnabled)
				[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"INSERT INTO jukeboxCurrentPlaylist SELECT * FROM splaylist%@", self.md5]];
			else
				[databaseControls.localPlaylistsDb executeUpdate:[NSString stringWithFormat:@"INSERT INTO currentPlaylist SELECT * FROM splaylist%@", self.md5]];
			[databaseControls.localPlaylistsDb executeUpdate:@"DETACH DATABASE currentPlaylistDb"];
		}
		
		if ([SavedSettings sharedInstance].isJukeboxEnabled)
		{
			[musicControls jukeboxReplacePlaylistWithLocal];
		}
			
		musicControls.isShuffle = NO;
		
		[musicControls playSongAtPosition:indexPath.row];
		
		if (IS_IPAD())
		{
			[[NSNotificationCenter defaultCenter] postNotificationName:@"showPlayer" object:nil];
		}
		else
		{
			iPhoneStreamingPlayerViewController *streamingPlayerViewController = [[iPhoneStreamingPlayerViewController alloc] initWithNibName:@"iPhoneStreamingPlayerViewController" bundle:nil];
			streamingPlayerViewController.hidesBottomBarWhenPushed = YES;
			[self.navigationController pushViewController:streamingPlayerViewController animated:YES];
			[streamingPlayerViewController release];
		}
	}
	else
	{
		[self.tableView deselectRowAtIndexPath:indexPath animated:NO];
	}
}


- (void)dealloc 
{
    [serverPlaylist release]; serverPlaylist = nil;
    [super dealloc];
}


#pragma mark -
#pragma mark Pull to refresh methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{	
	if (scrollView.isDragging && !viewObjects.isLocalPlaylist) 
	{
		if (refreshHeaderView.state == EGOOPullRefreshPulling && scrollView.contentOffset.y > -65.0f && scrollView.contentOffset.y < 0.0f && !_reloading) 
		{
			[refreshHeaderView setState:EGOOPullRefreshNormal];
		} 
		else if (refreshHeaderView.state == EGOOPullRefreshNormal && scrollView.contentOffset.y < -65.0f && !_reloading) 
		{
			[refreshHeaderView setState:EGOOPullRefreshPulling];
		}
	}
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
	
	if (scrollView.contentOffset.y <= - 65.0f && !_reloading && !viewObjects.isLocalPlaylist) 
	{
		_reloading = YES;
		//[self reloadAction:nil];
		[self loadData];
		[refreshHeaderView setState:EGOOPullRefreshLoading];
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.2];
		self.tableView.contentInset = UIEdgeInsetsMake(60.0f, 0.0f, 0.0f, 0.0f);
		[UIView commitAnimations];
	}
}

- (void)dataSourceDidFinishLoadingNewData
{
	_reloading = NO;
	
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:.3];
	[self.tableView setContentInset:UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f)];
	[UIView commitAnimations];
	
	[refreshHeaderView setState:EGOOPullRefreshNormal];
}



@end

