package Bluetree2;

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
export BluetreeServerPacket(..);
export BluetreeClientPacket(..);
export BluetreeMessageType(..);
export BluetreeClientMessageType(..);

export bluetreeBlockSize;
export bluetreeDataSize;
export bluetreeBlockAddressSize;
export bluetreeByteAddressSize;
export bluetreeWordAddressSize;
export bluetreeAddressSize;
export bluetreeBENSize;
export bluetreeBurstCounterSize;
export bluetreePrioritySize;

export BluetreeClientType(..);
export BluetreeServerType(..);
export BluetreeRoutable(..);
export BluetreePriorityOrdering(..);
export BluetreeDataContainer(..);
export IfcBluetree2Mux2(..);

import BluetreeConfig::*;
import GetPut::*;
import ClientServer::*;
import DReg::*;
import FIFO::*;

typedef SizeOf#(BluetreeData) DataSize;
Integer bluetreeDataSize = valueOf(DataSize);

typedef SizeOf#(BluetreeBEN) BENSize;
Integer bluetreeBENSize = valueOf(BENSize);

typedef SizeOf#(BluetreeBlockAddress) BlockAddressSize;
Integer bluetreeBlockAddressSize = valueOf(BlockAddressSize);

typedef SizeOf#(BluetreeByteAddress) ByteAddressSize;
Integer bluetreeByteAddressSize = valueOf(ByteAddressSize);

typedef SizeOf#(BluetreeWordAddress) WordAddressSize;
Integer bluetreeWordAddressSize = valueOf(WordAddressSize);

typedef SizeOf#(BluetreeAddress) AddressSize;
Integer bluetreeAddressSize = valueOf(AddressSize);

Integer bluetreeBlockSize = bluetreeBENSize;

typedef SizeOf#(BluetreeBurstCounter) BurstCounterSize;
Integer bluetreeBurstCounterSize = valueOf(BurstCounterSize);

typedef SizeOf#(BluetreePriority) PrioritySize;
Integer bluetreePrioritySize = valueOf(PrioritySize);

// BT_MEM_SCHEDULED is to notify multiplexors of which CPU has been scheduled.
typedef enum {BT_READ = 0, BT_BROADCAST, BT_PREFETCH, BT_WRITE_ACK, BT_AXI_PROBE, BT_SQUASH, BT_MEM_SCHEDULED}
            BluetreeMessageType deriving (Bits, Eq);

// Standard = normal mem request. Prefetch is to signify a prefetch packet and is currently largely
// unused. Prefetch hit denotes that a prefetched packet was hit and so another prefetch should be generated.
// BT_AXI_PROBE is used for sending a command to the AXI bus.
typedef enum {BT_STANDARD = 0, BT_PREFETCH, BT_PREFETCH_HIT, BT_AXI_PROBE}
            BluetreeClientMessageType deriving (Bits, Eq);

typedef struct {
    BluetreeClientMessageType   message_type;
    BluetreeData                data;
    BluetreeBEN                 ben;
    BluetreeBlockAddress        address;
    BluetreeTaskId              task_id;
    BluetreeCPUId               cpu_id;
    BluetreePriority            prio;
    BluetreeBurstCounter        size;
} BluetreeClientPacket deriving (Bits, Eq);

typedef struct {
    BluetreeMessageType     message_type;
    BluetreeData            data;
    BluetreeBlockAddress    address;
    BluetreeTaskId          task_id;
    BluetreeCPUId           cpu_id;
} BluetreeServerPacket deriving (Bits, Eq);


typeclass BluetreeClientType#(type packet);
    function BluetreeClientMessageType getClientMessageType(packet x);
    function packet setClientMessageType(packet x, BluetreeClientMessageType t);
endtypeclass

typeclass BluetreeServerType#(type packet);
    function BluetreeMessageType getMessageType(packet x);
    function packet setMessageType(packet x, BluetreeMessageType t);
endtypeclass

typeclass BluetreeRoutable#(type packet, type cpu_id)
    provisos(Bitwise#(cpu_id))
    dependencies(packet determines cpu_id);
    function cpu_id getCpuId(packet x);
    function packet setCpuId(packet x, cpu_id id);
endtypeclass

typeclass BluetreePriorityOrdering#(type packet, type prio_id)
    provisos(Ord#(prio_id))
    dependencies(packet determines prio_id);
    function prio_id getCpuPrio(packet x);
    function packet  setCpuPrio(packet x, prio_id id);
endtypeclass

typeclass BluetreeDataContainer#(type packet, type data_type)
    dependencies(packet determines data_type);
    function data_type getData(packet x);
    function packet    setData(packet x, data_type d);
endtypeclass

// Extend the current Bluetree packets
instance BluetreeClientType#(BluetreeClientPacket);
    function BluetreeClientMessageType getClientMessageType(BluetreeClientPacket x);
        return x.message_type;
    endfunction

    function BluetreeClientPacket setClientMessageType(BluetreeClientPacket x, BluetreeClientMessageType t);
        x.message_type = t;
        return x;
    endfunction
endinstance

instance BluetreeServerType#(BluetreeServerPacket);
    function BluetreeMessageType getMessageType(BluetreeServerPacket x);
        return x.message_type;
    endfunction

    function BluetreeServerPacket setMessageType(BluetreeServerPacket x, BluetreeMessageType t);
        x.message_type = t;
        return x;
    endfunction
endinstance

instance BluetreeRoutable#(BluetreeClientPacket, BluetreeCPUId);
    function BluetreeCPUId getCpuId(BluetreeClientPacket x);
        return x.cpu_id;
    endfunction

    function BluetreeClientPacket setCpuId(BluetreeClientPacket x, BluetreeCPUId cpu_id);
        x.cpu_id = cpu_id;
        return x;
    endfunction
endinstance

instance BluetreeRoutable#(BluetreeServerPacket, BluetreeCPUId);
    function BluetreeCPUId getCpuId(BluetreeServerPacket x);
        return x.cpu_id;
    endfunction

    function BluetreeServerPacket setCpuId(BluetreeServerPacket x, BluetreeCPUId cpu_id);
        x.cpu_id = cpu_id;
        return x;
    endfunction
endinstance

instance BluetreePriorityOrdering#(BluetreeClientPacket, BluetreePriority);
    function BluetreePriority getCpuPrio(BluetreeClientPacket x);
        return x.prio;
    endfunction

    function BluetreeClientPacket setCpuPrio(BluetreeClientPacket x, BluetreePriority id);
        x.prio = id;
        return x;
    endfunction
endinstance

interface IfcBluetree2Mux2#(type client_pkt, type server_pkt);
    interface Client#(client_pkt, server_pkt) client;
    interface Server#(client_pkt, server_pkt) server0;
    interface Server#(client_pkt, server_pkt) server1;
endinterface

endpackage
