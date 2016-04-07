// The width of all fields in Bluetree. Make sure to change all XPS projects
// if anything in this file is changed!
package BluetreeConfig;

export BluetreeTaskId;
export BluetreeCPUId;
export BluetreeData;
export BluetreeBEN;
export BluetreeAddress;
export BluetreeBlockAddress;
export BluetreeByteAddress;
export BluetreeWordAddress;
export BluetreeBurstCounter;
export BluetreePriority;

typedef Bit#(8) BluetreeTaskId;
typedef Bit#(8) BluetreeCPUId;
typedef Bit#(128) BluetreeData;
typedef Bit#(28) BluetreeBlockAddress;
typedef Bit#(16) BluetreeBEN;
typedef Bit#(4) BluetreeByteAddress;
typedef Bit#(2) BluetreeWordAddress;
typedef Bit#(32) BluetreeAddress;
typedef Bit#(4) BluetreeBurstCounter;
typedef Bit#(4) BluetreePriority;


endpackage

