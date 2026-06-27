/*
 * AppController.j
 * FHIR R6 Eligibility Criteria Editor
 *
 * Created by Daniel Böhringer 2026.
 * Implements interactive rule-based FHIR R6 Group generation.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>

// Helper to allow native JS object serialization to work nicely in Cappuccino
@implementation CPDictionary (JSONHelper)
- (id)JSObject
{
    var obj = {};
    var keys = [self allKeys];
    for (var i = 0; i < [keys count]; i++)
    {
        var key = keys[i];
        var val = [self objectForKey:key];
        
        if ([val respondsToSelector:@selector(JSObject)])
            obj[key] = [val JSObject];
        else if ([val isKindOfClass:[CPArray class]])
            obj[key] = [val JSObject];
        else
            obj[key] = val;
    }
    return obj;
}
@end

@implementation CPArray (JSONHelper)
- (id)JSObject
{
    var arr = [];
    for (var i = 0; i < [self count]; i++)
    {
        var val = [self objectAtIndex:i];
        if ([val respondsToSelector:@selector(JSObject)])
            [arr addObject:[val JSObject]];
        else
            [arr addObject:val];
    }
    return arr;
}
@end


// --------------------------------------------------------------------------------
// FHIRRuleEditor Subclass
// --------------------------------------------------------------------------------

@implementation FHIRRuleEditor : CPRuleEditor
{
    BOOL _insertCompoundMode;
}

- (void)setInsertCompoundMode:(BOOL)flag
{
    _insertCompoundMode = flag;
}

- (BOOL)insertCompoundMode
{
    return _insertCompoundMode;
}

// Intercepts the inline "+" button clicks on the slices to force compound row generation if toggled
- (void)_addOptionFromSlice:(id)slice ofRowType:(unsigned int)type
{
    var forcedType = _insertCompoundMode ? CPRuleEditorRowTypeCompound : CPRuleEditorRowTypeSimple;
    [super _addOptionFromSlice:slice ofRowType:forcedType];
}

@end


// --------------------------------------------------------------------------------
// FHIRCriteriaWindowController
// --------------------------------------------------------------------------------

@implementation FHIRCriteriaWindowController : CPWindowController
{
    FHIRRuleEditor       _ruleEditor;
    FHIRRuleDelegate     _ruleDelegate;
    CPTextView           _jsonTextView;
    CPSegmentedControl   _modeSegmentedControl;
    
    CPButton            _addRuleBtn;
    CPButton            _addGroupBtn;
    CPButton            _clearBtn;

    CPArray             _currentTextFields;
    int                 _currentTextFieldIndex;
}

- (id)initWithContentRect:(CGRect)aRect
{
    // CPBorderlessBridgeWindowMask makes this a bridged window matching the browser viewport
    var theWindow = [[CPWindow alloc] initWithContentRect:CGRectMakeZero() styleMask:CPBorderlessBridgeWindowMask];

    self = [super initWithWindow:theWindow];
    if (self)
    {
        [self _buildInterface];
    }
    return self;
}

- (void)_buildInterface
{
    var window = [self window],
        contentView = [window contentView],
        bounds = [contentView bounds];

    // Main Split View: Left side is Rule Editor, Right side is Live FHIR JSON
    var mainSplitView = [[CPSplitView alloc] initWithFrame:bounds];
    [mainSplitView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [mainSplitView setVertical:YES];
    
    // --- LEFT COLUMN: Editor & Control Buttons ---
    var leftContainer = [[CPView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(bounds) * 0.55, CGRectGetHeight(bounds))];
    [leftContainer setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    
    // Mode Segmented Control: Switches what clicking "+" inside the editor does
    _modeSegmentedControl = [[CPSegmentedControl alloc] initWithFrame:CGRectMake(10, 10, 240, 24)];
    [_modeSegmentedControl setSegmentCount:2];
    [_modeSegmentedControl setLabel:@"Add Criterion (+)" forSegment:0];
    [_modeSegmentedControl setLabel:@"Add Group (+)" forSegment:1];
    [_modeSegmentedControl setSelectedSegment:0];
    [_modeSegmentedControl setTarget:self];
    [_modeSegmentedControl setAction:@selector(modeSegmentedControlDidChange:)];
    [leftContainer addSubview:_modeSegmentedControl];

    // Shift rule editor scroll view down by 35px to clear the segmented control
    var ruleEditorY = 45.0;
    var ruleEditorHeight = CGRectGetHeight(bounds) - 75.0 - 35.0;
    
    var ruleScrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(10, ruleEditorY, CGRectGetWidth([leftContainer bounds]) - 20, ruleEditorHeight)];
    [ruleScrollView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [ruleScrollView setAutohidesScrollers:YES];
    [ruleScrollView setBorderType:CPBezelBorder];

    _ruleEditor = [[FHIRRuleEditor alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth([ruleScrollView bounds]), ruleEditorHeight)];
    [_ruleEditor setRowHeight:28.0];
    [_ruleEditor setCanRemoveAllRows:YES];
    [_ruleEditor setNestingMode:CPRuleEditorNestingModeCompound]; // Enables nesting (AND / OR blocks)
    [_ruleEditor setAutoresizingMask:CPViewWidthSizable];

    _ruleDelegate = [[FHIRRuleDelegate alloc] initWithController:self];
    [_ruleEditor setDelegate:_ruleDelegate];

    // Connect update target and action
    [_ruleEditor setTarget:self];
    [_ruleEditor setAction:@selector(ruleEditorDidChange:)];

    [ruleScrollView setDocumentView:_ruleEditor];
    [leftContainer addSubview:ruleScrollView];

    // Bottom Action Bar
    var btnY = CGRectGetHeight(bounds) - 50.0;
    
    _addRuleBtn = [[CPButton alloc] initWithFrame:CGRectMake(10, btnY, 110, 24)];
    [_addRuleBtn setTitle:@"Add Criterion"];
    [_addRuleBtn setTarget:self];
    [_addRuleBtn setAction:@selector(addSimpleRule:)];
    [_addRuleBtn setToolTip:@"Adds a simple clinical characteristic condition."];
    [leftContainer addSubview:_addRuleBtn];

    _addGroupBtn = [[CPButton alloc] initWithFrame:CGRectMake(130, btnY, 110, 24)];
    [_addGroupBtn setTitle:@"Add Group"];
    [_addGroupBtn setTarget:self];
    [_addGroupBtn setAction:@selector(addGroupRule:)];
    [_addGroupBtn setToolTip:@"Adds a logical nested Group (AND / OR combination)."];
    [leftContainer addSubview:_addGroupBtn];

    _clearBtn = [[CPButton alloc] initWithFrame:CGRectMake(250, btnY, 90, 24)];
    [_clearBtn setTitle:@"Reset"];
    [_clearBtn setTarget:self];
    [_clearBtn setAction:@selector(resetEditor:)];
    [leftContainer addSubview:_clearBtn];

    // --- RIGHT COLUMN: JSON Viewer ---
    var rightContainer = [[CPView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(bounds) * 0.45, CGRectGetHeight(bounds))];
    [rightContainer setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    var titleLabel = [CPTextField labelWithTitle:@"Generated FHIR R6 Group JSON (Live):"];
    [titleLabel setFrameOrigin:CGPointMake(10, 10)];
    [titleLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [rightContainer addSubview:titleLabel];

    var jsonScrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(10, 32, CGRectGetWidth([rightContainer bounds]) - 20, CGRectGetHeight(bounds) - 45.0)];
    [jsonScrollView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [jsonScrollView setAutohidesScrollers:YES];

    _jsonTextView = [[CPTextView alloc] initWithFrame:[jsonScrollView bounds]];
    [_jsonTextView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_jsonTextView setEditable:NO];
    [_jsonTextView setFont:[CPFont fontWithName:@"Courier" size:12.0]];
    [_jsonTextView setTextColor:[CPColor colorWithRed:0.1 green:0.4 blue:0.1 alpha:1.0]];

    [jsonScrollView setDocumentView:_jsonTextView];
    [rightContainer addSubview:jsonScrollView];

    // Add views to split view
    [mainSplitView addSubview:leftContainer];
    [mainSplitView addSubview:rightContainer];
    [contentView addSubview:mainSplitView];

    // Set initial configuration
    [self resetEditor:self];
    
    // Register observation for automatic synchronization
    [[CPNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(ruleEditorDidChange:) 
                                                 name:CPRuleEditorRowsDidChangeNotification 
                                               object:_ruleEditor];
}

- (void)modeSegmentedControlDidChange:(id)sender
{
    var selectedSegment = [sender selectedSegment];
    [_ruleEditor setInsertCompoundMode:(selectedSegment === 1)];
}

- (void)addSimpleRule:(id)sender
{
    var selectedRows = [_ruleEditor selectedRowIndexes];
    var targetIndex = [selectedRows count] > 0 ? [selectedRows lastIndex] + 1 : [_ruleEditor numberOfRows];
    
    [_ruleEditor insertRowAtIndex:targetIndex 
                         withType:CPRuleEditorRowTypeSimple 
                    asSubrowOfRow:-1 
                          animate:YES];
}

- (void)addGroupRule:(id)sender
{
    var selectedRows = [_ruleEditor selectedRowIndexes];
    var targetIndex = [selectedRows count] > 0 ? [selectedRows lastIndex] + 1 : [_ruleEditor numberOfRows];
    
    [_ruleEditor insertRowAtIndex:targetIndex 
                         withType:CPRuleEditorRowTypeCompound 
                    asSubrowOfRow:-1 
                          animate:YES];
}

- (void)resetEditor:(id)sender
{
    var count = [_ruleEditor numberOfRows];
    if (count > 0)
    {
        var indexes = [CPIndexSet indexSetWithIndexesInRange:NSMakeRange(0, count)];
        [_ruleEditor removeRowsAtIndexes:indexes includeSubrows:YES];
    }
        
    [_ruleEditor addRow:self];
    [self updateFHIRGroupRepresentation];
}

- (void)ruleEditorDidChange:(id)sender
{
    [self updateFHIRGroupRepresentation];
}

// --------------------------------------------------------------------------------
// View Hierarchy Scanning Helpers
// --------------------------------------------------------------------------------

- (CPArray)_allEditableTextFields
{
    var textFields = [CPMutableArray array];
    [self _collectEditableTextFieldsFromView:_ruleEditor intoArray:textFields];
    
    // Sort array using Cappuccino's native sortUsingFunction:context: method
    [textFields sortUsingFunction:function(tf1, tf2, context) {
        var origin1 = [tf1 convertPoint:CGPointMakeZero() toView:nil];
        var origin2 = [tf2 convertPoint:CGPointMakeZero() toView:nil];
        
        if (origin1.y < origin2.y) return -1;
        if (origin1.y > origin2.y) return 1;
        if (origin1.x < origin2.x) return -1;
        if (origin1.x > origin2.x) return 1;
        return 0;
    } context:nil];
    
    return textFields;
}

- (void)_collectEditableTextFieldsFromView:(CPView)aView intoArray:(CPMutableArray)array
{
    if ([aView isKindOfClass:[CPTextField class]] && [aView isEditable])
    {
        [array addObject:aView];
        return;
    }
    
    var subviews = [aView subviews];
    for (var i = 0; i < [subviews count]; i++)
    {
        [self _collectEditableTextFieldsFromView:subviews[i] intoArray:array];
    }
}

// --------------------------------------------------------------------------------
// FHIR Compiler Logic
// --------------------------------------------------------------------------------

- (void)updateFHIRGroupRepresentation
{
    // Retrieve currently mounted text field instances inside the editor
    _currentTextFields = [self _allEditableTextFields];
    _currentTextFieldIndex = 0;

    var containedArray = [CPMutableArray array];
    var subgroupCounter = { value: 0 }; 
    
    var rootGroup;
    var hasRootCompound = ([_ruleEditor numberOfRows] > 0 && [_ruleEditor rowTypeForRow:0] == CPRuleEditorRowTypeCompound);
    
    if (hasRootCompound)
    {
        rootGroup = [self _compileGroupForRowIndex:0 containedArray:containedArray subgroupCounter:subgroupCounter];
    }
    else
    {
        rootGroup = [self _compileGroupForRowIndex:-1 containedArray:containedArray subgroupCounter:subgroupCounter];
    }
    
    [rootGroup setObject:@"Group" forKey:@"resourceType"];
    [rootGroup setObject:@"eligibility-criteria" forKey:@"id"];
    [rootGroup setObject:@"active" forKey:@"status"];
    [rootGroup setObject:@"definitional" forKey:@"membership"];
    [rootGroup setObject:@"person" forKey:@"type"];
    
    var rootCombMethod = "all-of";
    if (hasRootCompound)
    {
        var criteria = [_ruleEditor criteriaForRow:0];
        if ([criteria count] > 0)
        {
            var methodVal = [criteria objectAtIndex:0];
            if (methodVal === CPOrPredicateType)
                rootCombMethod = "any-of";
        }
    }
    [rootGroup setObject:rootCombMethod forKey:@"combinationMethod"];
    
    if ([containedArray count] > 0)
    {
        [rootGroup setObject:containedArray forKey:@"contained"];
    }
    
    var jsFormattedObject = [rootGroup JSObject];
    var prettyJson = JSON.stringify(jsFormattedObject, null, 2);
    
    [_jsonTextView setString:prettyJson];
}

- (CPMutableDictionary)_compileGroupForRowIndex:(CPInteger)rowIndex containedArray:(CPMutableArray)containedArray subgroupCounter:(id)subgroupCounter
{
    var group = [CPMutableDictionary dictionary];
    [group setObject:@"Group" forKey:@"resourceType"];
    
    var subrowIndexes = [_ruleEditor subrowIndexesForRow:rowIndex];
    var characteristics = [CPMutableArray array];
    
    var current_index = [subrowIndexes firstIndex];
    while (current_index !== CPNotFound)
    {
        var rowType = [_ruleEditor rowTypeForRow:current_index];
        
        if (rowType == CPRuleEditorRowTypeCompound)
        {
            subgroupCounter.value = subgroupCounter.value + 1;
            var subgroupID = "subgroup-" + subgroupCounter.value;
            
            var subGroup = [self _compileGroupForRowIndex:current_index containedArray:containedArray subgroupCounter:subgroupCounter];
            [subGroup setObject:subgroupID forKey:@"id"];
            [subGroup setObject:@"conceptual" forKey:@"membership"];
            [subGroup setObject:@"person" forKey:@"type"];
            
            var criteria = [_ruleEditor criteriaForRow:current_index];
            var combMethod = "all-of";
            if ([criteria count] > 0)
            {
                var methodVal = [criteria objectAtIndex:0];
                if (methodVal === CPOrPredicateType)
                    combMethod = "any-of";
            }
            [subGroup setObject:combMethod forKey:@"combinationMethod"];
            
            [containedArray addObject:subGroup];
            
            var refCharacteristic = [CPMutableDictionary dictionary];
            [refCharacteristic setObject:@{ @"text": @"Logical subgroup" } forKey:@"code"];
            [refCharacteristic setObject:@{ @"reference": "#" + subgroupID } forKey:@"valueReference"];
            [refCharacteristic setObject:NO forKey:@"exclude"];
            
            [characteristics addObject:refCharacteristic];
        }
        else // Simple Criterion
        {
            var criteria = [_ruleEditor criteriaForRow:current_index];
            
            if ([criteria count] >= 3)
            {
                var presence = [criteria objectAtIndex:1]; // "inclusion" or "exclusion"
                
                // Align chronological compilation with vertically sorted view elements
                var rawText = @"";
                if (_currentTextFieldIndex < [_currentTextFields count])
                {
                    var textField = [_currentTextFields objectAtIndex:_currentTextFieldIndex];
                    rawText = [textField stringValue] || @"";
                    _currentTextFieldIndex++;
                }
                
                var clinicalTerm = [rawText stringByTrimmingCharactersInSet:[CPCharacterSet whitespaceAndNewlineCharacterSet]];
                var hpoTermName = [clinicalTerm isEqualToString:@""] ? @"UNDEFINED" : clinicalTerm;
                
                var formattedTerm = hpoTermName.toUpperCase().replace(/\s+/g, '_');
                var hpoCodePlaceholder = "[HPO_CODE_FOR_" + formattedTerm + "]";
                
                var charItem = [CPMutableDictionary dictionary];
                
                [charItem setObject:@{
                    @"coding": [
                        @{
                            @"system": @"http://snomed.info/sct",
                            @"code": @"8116006",
                            @"display": @"Phänotypisches Merkmal"
                        }
                    ]
                } forKey:@"code"];
                
                [charItem setObject:@{
                    @"coding": [
                        @{
                            @"system": @"http://human-phenotype-ontology.org",
                            @"code": hpoCodePlaceholder,
                            @"display": hpoTermName
                        }
                    ]
                } forKey:@"valueCodeableConcept"];
                
                var isExclude = [presence isEqualToString:@"exclusion"];
                [charItem setObject:isExclude forKey:@"exclude"]; // native JS boolean output
                
                [characteristics addObject:charItem];
            }
        }
        
        current_index = [subrowIndexes indexGreaterThanIndex:current_index];
    }
    
    [group setObject:characteristics forKey:@"characteristic"];
    return group;
}

@end


// --------------------------------------------------------------------------------
// FHIRRuleDelegate
// --------------------------------------------------------------------------------

@implementation FHIRRuleDelegate : CPObject
{
    id _controller;
}

- (id)initWithController:(id)aController
{
    self = [super init];
    if (self)
    {
        _controller = aController;
    }
    return self;
}

- (int)ruleEditor:(CPRuleEditor)editor numberOfChildrenForCriterion:(id)criterion withRowType:(CPRuleEditorRowType)rowType
{
    if (rowType === CPRuleEditorRowTypeCompound)
    {
        if (criterion == nil) return 2; // "Any" / "All"
        if (criterion == CPOrPredicateType || criterion == CPAndPredicateType) return 1; // logical text
        return 0;
    }

    if (rowType === CPRuleEditorRowTypeSimple)
    {
        if (criterion == nil) return 1; // "Phenotypic Feature"
        if (criterion == @"phenotype") return 2; // "Inclusion" vs "Exclusion"
        if (criterion == @"inclusion" || criterion == @"exclusion") return 1; // text input placeholder
    }
    return 0;
}

- (id)ruleEditor:(CPRuleEditor)editor child:(int)index forCriterion:(id)criterion withRowType:(CPRuleEditorRowType)rowType
{
    if (rowType === CPRuleEditorRowTypeCompound)
    {
        if (criterion == nil)
            return (index == 0) ? CPAndPredicateType : CPOrPredicateType;
            
        return @"_logical_text_";
    }

    if (criterion == nil)
        return @"phenotype";
        
    if (criterion == @"phenotype")
        return (index == 0) ? @"inclusion" : @"exclusion";
        
    if (criterion == @"inclusion" || criterion == @"exclusion")
        return @"_value_field_";
        
    return nil;
}

- (id)ruleEditor:(CPRuleEditor)editor displayValueForCriterion:(id)criterion inRow:(int)row
{
    if (criterion === CPAndPredicateType) return @"All";
    if (criterion === CPOrPredicateType) return @"Any";
    if (criterion === @"_logical_text_") return @"of the following are true";

    if (criterion == @"phenotype") return @"Symptom / Phenotype";
    if (criterion == @"inclusion") return @"Must be present (Inclusion)";
    if (criterion == @"exclusion") return @"Must NOT be present (Exclusion)";

    if (criterion == @"_value_field_")
    {
        var inputField = [[CPTextField alloc] initWithFrame:CGRectMake(0, 0, 160, 24)];
        [inputField setEditable:YES];
        [inputField setBezeled:YES];
        [inputField setBackgroundColor:[CPColor whiteColor]];
        [inputField setPlaceholderString:@"e.g., Corneal erosion"];
        
        [inputField setTarget:_controller];
        [inputField setAction:@selector(ruleEditorDidChange:)];
        
        // Listen to every continuous text change keystroke to keep the live JSON updated
        [[CPNotificationCenter defaultCenter] addObserver:_controller 
                                                 selector:@selector(ruleEditorDidChange:) 
                                                     name:CPControlTextDidChangeNotification 
                                                   object:inputField];
        
        return inputField;
    }
    
    return criterion;
}

- (CPDictionary)ruleEditor:(CPRuleEditor)editor predicatePartsForCriterion:(id)criterion withDisplayValue:(id)value inRow:(int)row
{
    var result = [CPMutableDictionary dictionary];
    
    if (criterion === CPOrPredicateType || criterion === CPAndPredicateType)
    {
        [result setObject:criterion forKey:CPRuleEditorPredicateCompoundType];
    }
    return result;
}

@end


// --------------------------------------------------------------------------------
// AppController
// --------------------------------------------------------------------------------

@implementation AppController : CPObject
{
    FHIRCriteriaWindowController _windowController;
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    _windowController = [[FHIRCriteriaWindowController alloc] initWithContentRect:CGRectMake(100, 100, 850, 600)];
    [_windowController showWindow:self];

    // Setup basic Application Menu
    var mainMenu = [CPApp mainMenu];
    while ([mainMenu numberOfItems] > 0)
       [mainMenu removeItemAtIndex:0];

    var item = [mainMenu insertItemWithTitle:@"Edit" action:nil keyEquivalent:nil atIndex:0],
        editMenu = [[CPMenu alloc] initWithTitle:@"Edit"];

    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

    [mainMenu setSubmenu:editMenu forItem:item];
    [CPMenu setMenuBarVisible:YES];
}

@end
