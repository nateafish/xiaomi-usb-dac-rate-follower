#include <algorithm>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr uint32_t kPtLoad = 1;
constexpr uint32_t kPtNote = 4;
constexpr uint32_t kPfExecute = 1;
constexpr uint16_t kMachineAArch64 = 183;
constexpr uint32_t kShtDynsym = 11;
constexpr uint32_t kShtRela = 4;
constexpr uint32_t kNtGnuBuildId = 3;
constexpr int64_t kDtNull = 0;
constexpr int64_t kDtSoname = 14;

#pragma pack(push, 1)
struct Elf64Ehdr {
    unsigned char ident[16];
    uint16_t type;
    uint16_t machine;
    uint32_t version;
    uint64_t entry;
    uint64_t phoff;
    uint64_t shoff;
    uint32_t flags;
    uint16_t ehsize;
    uint16_t phentsize;
    uint16_t phnum;
    uint16_t shentsize;
    uint16_t shnum;
    uint16_t shstrndx;
};

struct Elf64Phdr {
    uint32_t type;
    uint32_t flags;
    uint64_t offset;
    uint64_t vaddr;
    uint64_t paddr;
    uint64_t filesz;
    uint64_t memsz;
    uint64_t align;
};

struct Elf64Shdr {
    uint32_t name;
    uint32_t type;
    uint64_t flags;
    uint64_t addr;
    uint64_t offset;
    uint64_t size;
    uint32_t link;
    uint32_t info;
    uint64_t addralign;
    uint64_t entsize;
};

struct Elf64Sym {
    uint32_t name;
    uint8_t info;
    uint8_t other;
    uint16_t shndx;
    uint64_t value;
    uint64_t size;
};

struct Elf64Dyn {
    int64_t tag;
    uint64_t value;
};

struct Elf64Rela {
    uint64_t offset;
    uint64_t info;
    int64_t addend;
};

struct Elf64Nhdr {
    uint32_t namesz;
    uint32_t descsz;
    uint32_t type;
};
#pragma pack(pop)

struct Pattern {
    std::vector<uint8_t> bytes;
    std::vector<uint8_t> mask;
};

struct Range {
    uint64_t begin;
    uint64_t end;
};

uint64_t parseNumber(const std::string& value) {
    size_t used = 0;
    const uint64_t result = std::stoull(value, &used, 0);
    if (used != value.size()) throw std::runtime_error("invalid number: " + value);
    return result;
}

std::vector<uint8_t> readFile(const std::string& path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("cannot open: " + path);
    stream.seekg(0, std::ios::end);
    const auto size = stream.tellg();
    if (size < 0) throw std::runtime_error("cannot size: " + path);
    stream.seekg(0, std::ios::beg);
    std::vector<uint8_t> data(static_cast<size_t>(size));
    if (!data.empty()) stream.read(reinterpret_cast<char*>(data.data()), size);
    if (!stream) throw std::runtime_error("cannot read: " + path);
    return data;
}

void writeFile(const std::string& path, const std::vector<uint8_t>& data) {
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) throw std::runtime_error("cannot write: " + path);
    if (!data.empty()) {
        stream.write(reinterpret_cast<const char*>(data.data()),
                     static_cast<std::streamsize>(data.size()));
    }
    if (!stream) throw std::runtime_error("short write: " + path);
}

uint8_t hexNibble(char value) {
    if (value >= '0' && value <= '9') return static_cast<uint8_t>(value - '0');
    if (value >= 'a' && value <= 'f') return static_cast<uint8_t>(value - 'a' + 10);
    if (value >= 'A' && value <= 'F') return static_cast<uint8_t>(value - 'A' + 10);
    throw std::runtime_error("invalid hexadecimal digit");
}

Pattern parsePattern(const std::string& text) {
    std::string compact;
    for (char value : text) {
        if (value != ' ' && value != ':' && value != '_') compact.push_back(value);
    }
    if (compact.empty() || compact.size() % 2 != 0) {
        throw std::runtime_error("pattern must contain complete byte pairs");
    }
    Pattern result;
    for (size_t index = 0; index < compact.size(); index += 2) {
        if (compact[index] == '?' && compact[index + 1] == '?') {
            result.bytes.push_back(0);
            result.mask.push_back(0);
        } else {
            result.bytes.push_back(static_cast<uint8_t>(
                    (hexNibble(compact[index]) << 4) | hexNibble(compact[index + 1])));
            result.mask.push_back(0xff);
        }
    }
    return result;
}

std::string hexBytes(const uint8_t* data, size_t size) {
    std::ostringstream stream;
    stream << std::hex << std::setfill('0');
    for (size_t index = 0; index < size; ++index) {
        stream << std::setw(2) << static_cast<unsigned>(data[index]);
    }
    return stream.str();
}

class ElfFile {
  public:
    explicit ElfFile(std::string path) : path_(std::move(path)), data_(readFile(path_)) {
        if (data_.size() < sizeof(Elf64Ehdr)) throw std::runtime_error("truncated ELF");
        std::memcpy(&header_, data_.data(), sizeof(header_));
        const unsigned char expected[] = {0x7f, 'E', 'L', 'F', 2, 1, 1};
        if (std::memcmp(header_.ident, expected, sizeof(expected)) != 0 ||
            header_.machine != kMachineAArch64) {
            throw std::runtime_error("not an ELF64 little-endian AArch64 file");
        }
        if (header_.phentsize != sizeof(Elf64Phdr) ||
            header_.shentsize != sizeof(Elf64Shdr)) {
            throw std::runtime_error("unsupported ELF table layout");
        }
        requireRange(header_.phoff,
                     static_cast<uint64_t>(header_.phnum) * header_.phentsize);
        requireRange(header_.shoff,
                     static_cast<uint64_t>(header_.shnum) * header_.shentsize);
        for (uint16_t index = 0; index < header_.phnum; ++index) {
            Elf64Phdr entry{};
            std::memcpy(&entry, data_.data() + header_.phoff + index * header_.phentsize,
                        sizeof(entry));
            programs_.push_back(entry);
        }
        for (uint16_t index = 0; index < header_.shnum; ++index) {
            Elf64Shdr entry{};
            std::memcpy(&entry, data_.data() + header_.shoff + index * header_.shentsize,
                        sizeof(entry));
            sections_.push_back(entry);
        }
        if (header_.shstrndx >= sections_.size()) {
            throw std::runtime_error("invalid section-name table");
        }
        const auto& names = sections_[header_.shstrndx];
        requireRange(names.offset, names.size);
        sectionNames_ = Range{names.offset, names.offset + names.size};
    }

    const std::vector<uint8_t>& data() const { return data_; }
    std::vector<uint8_t>& mutableData() { return data_; }
    const std::string& path() const { return path_; }

    void save() const { writeFile(path_, data_); }

    std::vector<Range> loadRanges(bool executableOnly) const {
        std::vector<Range> result;
        for (const auto& program : programs_) {
            if (program.type != kPtLoad || program.filesz == 0) continue;
            if (executableOnly && !(program.flags & kPfExecute)) continue;
            requireRange(program.offset, program.filesz);
            result.push_back(Range{program.offset, program.offset + program.filesz});
        }
        return result;
    }

    bool isExecutableRange(uint64_t offset, uint64_t size) const {
        for (const auto& range : loadRanges(true)) {
            if (offset >= range.begin && size <= range.end - offset) return true;
        }
        return false;
    }

    uint64_t offsetToVaddr(uint64_t offset) const {
        for (const auto& program : programs_) {
            if (program.type != kPtLoad) continue;
            if (offset >= program.offset && offset < program.offset + program.filesz) {
                return program.vaddr + offset - program.offset;
            }
        }
        throw std::runtime_error("file offset is outside a load segment");
    }

    uint64_t vaddrToOffset(uint64_t address) const {
        for (const auto& program : programs_) {
            if (program.type != kPtLoad) continue;
            if (address >= program.vaddr && address < program.vaddr + program.filesz) {
                return program.offset + address - program.vaddr;
            }
        }
        throw std::runtime_error("virtual address is outside a file-backed load segment");
    }

    std::optional<Range> symbolRange(const std::string& name) const {
        for (const auto& symbols : sections_) {
            if (symbols.type != kShtDynsym || symbols.entsize != sizeof(Elf64Sym) ||
                symbols.link >= sections_.size()) continue;
            const auto& strings = sections_[symbols.link];
            requireRange(symbols.offset, symbols.size);
            requireRange(strings.offset, strings.size);
            for (uint64_t cursor = 0; cursor + sizeof(Elf64Sym) <= symbols.size;
                 cursor += sizeof(Elf64Sym)) {
                Elf64Sym symbol{};
                std::memcpy(&symbol, data_.data() + symbols.offset + cursor, sizeof(symbol));
                if (symbol.name >= strings.size || symbol.value == 0) continue;
                const char* candidate = reinterpret_cast<const char*>(
                        data_.data() + strings.offset + symbol.name);
                const size_t remaining = static_cast<size_t>(strings.size - symbol.name);
                if (std::memchr(candidate, '\0', remaining) == nullptr) continue;
                if (name != candidate) continue;
                const uint64_t begin = vaddrToOffset(symbol.value);
                if (symbol.size == 0) {
                    throw std::runtime_error("symbol has no bounded size: " + name);
                }
                requireRange(begin, symbol.size);
                return Range{begin, begin + symbol.size};
            }
        }
        return std::nullopt;
    }

    uint64_t symbolOffset(const std::string& name) const {
        const auto range = symbolRange(name);
        if (!range) throw std::runtime_error("dynamic symbol not found: " + name);
        return range->begin;
    }

    uint64_t pltOffset(const std::string& name) const {
        const auto* relocations = findSection(".rela.plt");
        const auto* plt = findSection(".plt");
        if (!relocations || !plt || relocations->type != kShtRela ||
            relocations->entsize != sizeof(Elf64Rela) ||
            relocations->link >= sections_.size()) {
            throw std::runtime_error("unsupported or missing PLT relocation table");
        }
        const auto& symbols = sections_[relocations->link];
        if (symbols.type != kShtDynsym || symbols.entsize != sizeof(Elf64Sym) ||
            symbols.link >= sections_.size()) {
            throw std::runtime_error("invalid PLT dynamic symbol table");
        }
        const auto& strings = sections_[symbols.link];
        requireRange(relocations->offset, relocations->size);
        requireRange(symbols.offset, symbols.size);
        requireRange(strings.offset, strings.size);
        requireRange(plt->offset, plt->size);
        const uint64_t count = relocations->size / sizeof(Elf64Rela);
        uint64_t entrySize = 0;
        uint64_t headerSize = 0;
        for (const uint64_t candidateEntry : {uint64_t{24}, uint64_t{16}}) {
            for (const uint64_t candidateHeader : {uint64_t{32}, uint64_t{16}}) {
                if (plt->size == candidateHeader + count * candidateEntry) {
                    entrySize = candidateEntry;
                    headerSize = candidateHeader;
                    break;
                }
            }
            if (entrySize != 0) break;
        }
        if (entrySize == 0) throw std::runtime_error("unknown AArch64 PLT layout");
        for (uint64_t index = 0; index < count; ++index) {
            Elf64Rela relocation{};
            std::memcpy(&relocation,
                        data_.data() + relocations->offset + index * sizeof(relocation),
                        sizeof(relocation));
            const uint64_t symbolIndex = relocation.info >> 32;
            if (symbolIndex >= symbols.size / sizeof(Elf64Sym)) continue;
            Elf64Sym symbol{};
            std::memcpy(&symbol,
                        data_.data() + symbols.offset + symbolIndex * sizeof(symbol),
                        sizeof(symbol));
            if (symbol.name >= strings.size) continue;
            const char* candidate = reinterpret_cast<const char*>(
                    data_.data() + strings.offset + symbol.name);
            const size_t remaining = static_cast<size_t>(strings.size - symbol.name);
            if (std::memchr(candidate, '\0', remaining) == nullptr) continue;
            if (name != candidate) continue;
            const uint64_t result = plt->offset + headerSize + index * entrySize;
            if (!isExecutableRange(result, entrySize)) {
                throw std::runtime_error("resolved PLT entry is not executable");
            }
            return result;
        }
        throw std::runtime_error("imported PLT symbol not found: " + name);
    }

    uint32_t read32(uint64_t offset) const {
        requireRange(offset, 4);
        uint32_t value = 0;
        std::memcpy(&value, data_.data() + offset, sizeof(value));
        return value;
    }

    std::string buildId() const {
        for (const auto& program : programs_) {
            if (program.type != kPtNote) continue;
            requireRange(program.offset, program.filesz);
            uint64_t cursor = program.offset;
            const uint64_t end = program.offset + program.filesz;
            while (cursor + sizeof(Elf64Nhdr) <= end) {
                Elf64Nhdr note{};
                std::memcpy(&note, data_.data() + cursor, sizeof(note));
                cursor += sizeof(note);
                const uint64_t nameEnd = cursor + note.namesz;
                const uint64_t descStart = (nameEnd + 3) & ~uint64_t(3);
                const uint64_t descEnd = descStart + note.descsz;
                if (descEnd > end) break;
                if (note.type == kNtGnuBuildId && note.namesz >= 3 &&
                    std::memcmp(data_.data() + cursor, "GNU", 3) == 0) {
                    return hexBytes(data_.data() + descStart, note.descsz);
                }
                cursor = (descEnd + 3) & ~uint64_t(3);
            }
        }
        return {};
    }

    std::string soname() const {
        const auto* dynamic = findSection(".dynamic");
        const auto* strings = findSection(".dynstr");
        if (!dynamic || !strings || dynamic->entsize != sizeof(Elf64Dyn)) return {};
        requireRange(dynamic->offset, dynamic->size);
        requireRange(strings->offset, strings->size);
        for (uint64_t cursor = 0; cursor + sizeof(Elf64Dyn) <= dynamic->size;
             cursor += sizeof(Elf64Dyn)) {
            Elf64Dyn entry{};
            std::memcpy(&entry, data_.data() + dynamic->offset + cursor, sizeof(entry));
            if (entry.tag == kDtNull) break;
            if (entry.tag != kDtSoname || entry.value >= strings->size) continue;
            const char* value = reinterpret_cast<const char*>(
                    data_.data() + strings->offset + entry.value);
            const size_t remaining = static_cast<size_t>(strings->size - entry.value);
            if (std::memchr(value, '\0', remaining) == nullptr) return {};
            return value;
        }
        return {};
    }

    std::vector<Range> resolveDomain(const std::string& domain) const {
        if (domain == "exec") return loadRanges(true);
        if (domain == "load") return loadRanges(false);
        const std::string symbolPrefix = "symbol:";
        const std::string rangePrefix = "range:";
        if (domain.rfind(symbolPrefix, 0) == 0) {
            auto result = symbolRange(domain.substr(symbolPrefix.size()));
            if (!result) throw std::runtime_error("dynamic symbol not found");
            return {*result};
        }
        if (domain.rfind(rangePrefix, 0) == 0) {
            const auto value = domain.substr(rangePrefix.size());
            const auto separator = value.find(':');
            if (separator == std::string::npos) throw std::runtime_error("bad range domain");
            const uint64_t begin = parseNumber(value.substr(0, separator));
            const uint64_t size = parseNumber(value.substr(separator + 1));
            requireRange(begin, size);
            return {Range{begin, begin + size}};
        }
        throw std::runtime_error("unknown search domain: " + domain);
    }

    uint64_t findUnique(const std::string& domain, const Pattern& pattern) const {
        std::vector<uint64_t> matches;
        for (const auto& range : resolveDomain(domain)) {
            if (pattern.bytes.size() > range.end - range.begin) continue;
            const uint64_t last = range.end - pattern.bytes.size();
            for (uint64_t offset = range.begin; offset <= last; ++offset) {
                bool equal = true;
                for (size_t index = 0; index < pattern.bytes.size(); ++index) {
                    if (pattern.mask[index] && data_[offset + index] != pattern.bytes[index]) {
                        equal = false;
                        break;
                    }
                }
                if (equal) matches.push_back(offset);
                if (matches.size() > 1) break;
            }
            if (matches.size() > 1) break;
        }
        if (matches.empty()) throw std::runtime_error("signature did not match");
        if (matches.size() != 1) throw std::runtime_error("signature matched more than once");
        return matches.front();
    }

    void requireRange(uint64_t offset, uint64_t size) const {
        if (offset > data_.size() || size > data_.size() - offset) {
            throw std::runtime_error("range is outside the file");
        }
    }

  private:
    std::string sectionName(const Elf64Shdr& section) const {
        if (section.name >= sectionNames_.end - sectionNames_.begin) return {};
        const char* value = reinterpret_cast<const char*>(
                data_.data() + sectionNames_.begin + section.name);
        const size_t remaining = static_cast<size_t>(sectionNames_.end -
                                                     sectionNames_.begin - section.name);
        if (std::memchr(value, '\0', remaining) == nullptr) return {};
        return value;
    }

    const Elf64Shdr* findSection(const std::string& name) const {
        for (const auto& section : sections_) {
            if (sectionName(section) == name) return &section;
        }
        return nullptr;
    }

    std::string path_;
    std::vector<uint8_t> data_;
    Elf64Ehdr header_{};
    std::vector<Elf64Phdr> programs_;
    std::vector<Elf64Shdr> sections_;
    Range sectionNames_{};
};

uint32_t encodeBranch(uint64_t fromAddress, uint64_t toAddress, bool link) {
    const int64_t delta = static_cast<int64_t>(toAddress) -
                          static_cast<int64_t>(fromAddress);
    if ((delta & 3) != 0 || delta < -(int64_t{1} << 27) ||
        delta >= (int64_t{1} << 27)) {
        throw std::runtime_error("AArch64 branch target is out of range or unaligned");
    }
    const uint32_t immediate = static_cast<uint32_t>((delta >> 2) & 0x03ffffff);
    return (link ? 0x94000000u : 0x14000000u) | immediate;
}

int64_t signExtend(uint64_t value, unsigned bits) {
    const uint64_t sign = uint64_t{1} << (bits - 1);
    return static_cast<int64_t>((value ^ sign) - sign);
}

uint64_t decodeBranchTarget(uint32_t instruction, uint64_t fromAddress) {
    int64_t delta = 0;
    if ((instruction & 0x7c000000u) == 0x14000000u) {
        delta = signExtend(instruction & 0x03ffffffu, 26) << 2;
    } else if ((instruction & 0xff000010u) == 0x54000000u ||
               (instruction & 0x7e000000u) == 0x34000000u) {
        delta = signExtend((instruction >> 5) & 0x7ffffu, 19) << 2;
    } else if ((instruction & 0x7e000000u) == 0x36000000u) {
        delta = signExtend((instruction >> 5) & 0x3fffu, 14) << 2;
    } else {
        throw std::runtime_error("instruction is not a supported AArch64 branch");
    }
    return static_cast<uint64_t>(static_cast<int64_t>(fromAddress) + delta);
}

void store32(std::vector<uint8_t>& data, uint64_t offset, uint32_t value);

void relocateBranch(std::vector<uint8_t>& data, uint64_t offset,
                    uint64_t fromAddress, uint64_t toAddress,
                    const std::string& kind) {
    if (offset > data.size() || 4 > data.size() - offset) {
        throw std::runtime_error("relocation is outside payload");
    }
    const int64_t delta = static_cast<int64_t>(toAddress) -
                          static_cast<int64_t>(fromAddress);
    if ((delta & 3) != 0) throw std::runtime_error("unaligned branch relocation");
    uint32_t instruction = 0;
    std::memcpy(&instruction, data.data() + offset, sizeof(instruction));
    if (kind == "B" || kind == "BL") {
        instruction = encodeBranch(fromAddress, toAddress, kind == "BL");
    } else if (kind == "COND19" || kind == "CB19") {
        if (delta < -(int64_t{1} << 20) || delta >= (int64_t{1} << 20)) {
            throw std::runtime_error("AArch64 imm19 branch target is out of range");
        }
        instruction &= ~(0x7ffffu << 5);
        instruction |= (static_cast<uint32_t>(delta >> 2) & 0x7ffffu) << 5;
    } else if (kind == "TB14") {
        if (delta < -(int64_t{1} << 15) || delta >= (int64_t{1} << 15)) {
            throw std::runtime_error("AArch64 imm14 branch target is out of range");
        }
        instruction &= ~(0x3fffu << 5);
        instruction |= (static_cast<uint32_t>(delta >> 2) & 0x3fffu) << 5;
    } else {
        throw std::runtime_error("unknown relocation kind: " + kind);
    }
    store32(data, offset, instruction);
}

void store32(std::vector<uint8_t>& data, uint64_t offset, uint32_t value) {
    if (offset > data.size() || 4 > data.size() - offset) {
        throw std::runtime_error("instruction write is outside the file");
    }
    data[offset] = static_cast<uint8_t>(value);
    data[offset + 1] = static_cast<uint8_t>(value >> 8);
    data[offset + 2] = static_cast<uint8_t>(value >> 16);
    data[offset + 3] = static_cast<uint8_t>(value >> 24);
}

void usage() {
    std::cerr
        << "usage:\n"
        << "  elfpatcher info ELF\n"
        << "  elfpatcher find ELF DOMAIN PATTERN\n"
        << "  elfpatcher symbol ELF NAME\n"
        << "  elfpatcher plt ELF NAME\n"
        << "  elfpatcher branch-target ELF OFFSET\n"
        << "  elfpatcher word ELF OFFSET\n"
        << "  elfpatcher replace ELF DOMAIN PATTERN DELTA REPLACEMENT\n"
        << "  elfpatcher assert-zero ELF OFFSET SIZE exec|load\n"
        << "  elfpatcher branch ELF FROM_OFFSET TO_OFFSET B|BL\n"
        << "  elfpatcher inject ELF CAVE_OFFSET TEMPLATE [RELOC_OFFSET:KIND:TARGET_OFFSET ...]\n"
        << "  elfpatcher patch-template ELF OFFSET EXPECTED TEMPLATE [RELOC_OFFSET:KIND:TARGET_OFFSET ...]\n";
}

void applyRelocations(const ElfFile& elf, uint64_t destination,
                      std::vector<uint8_t>& payload, int argc, char** argv,
                      int firstArgument) {
    const uint64_t base = elf.offsetToVaddr(destination);
    for (int index = firstArgument; index < argc; ++index) {
        const std::string spec = argv[index];
        const size_t first = spec.find(':');
        const size_t second = spec.find(':', first == std::string::npos ? first : first + 1);
        if (first == std::string::npos || second == std::string::npos) {
            throw std::runtime_error("bad relocation: " + spec);
        }
        const uint64_t at = parseNumber(spec.substr(0, first));
        const std::string kind = spec.substr(first + 1, second - first - 1);
        const uint64_t target = parseNumber(spec.substr(second + 1));
        relocateBranch(payload, at, base + at, elf.offsetToVaddr(target), kind);
    }
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc < 3) {
            usage();
            return 2;
        }
        const std::string command = argv[1];
        ElfFile elf(argv[2]);

        if (command == "info" && argc == 3) {
            std::cout << "machine=aarch64\n";
            std::cout << "build_id=" << elf.buildId() << "\n";
            std::cout << "soname=" << elf.soname() << "\n";
            for (const auto& range : elf.loadRanges(true)) {
                std::cout << "exec_range=0x" << std::hex << range.begin << ":0x"
                          << (range.end - range.begin) << "\n";
            }
            return 0;
        }

        if (command == "find" && argc == 5) {
            const uint64_t offset = elf.findUnique(argv[3], parsePattern(argv[4]));
            std::cout << "0x" << std::hex << offset << "\n";
            return 0;
        }

        if (command == "symbol" && argc == 4) {
            std::cout << "0x" << std::hex << elf.symbolOffset(argv[3]) << "\n";
            return 0;
        }

        if (command == "plt" && argc == 4) {
            std::cout << "0x" << std::hex << elf.pltOffset(argv[3]) << "\n";
            return 0;
        }

        if (command == "branch-target" && argc == 4) {
            const uint64_t from = parseNumber(argv[3]);
            if (!elf.isExecutableRange(from, 4)) {
                throw std::runtime_error("branch instruction is not executable");
            }
            const uint64_t targetAddress = decodeBranchTarget(
                    elf.read32(from), elf.offsetToVaddr(from));
            std::cout << "0x" << std::hex << elf.vaddrToOffset(targetAddress) << "\n";
            return 0;
        }

        if (command == "word" && argc == 4) {
            const uint64_t offset = parseNumber(argv[3]);
            std::cout << "0x" << std::hex << elf.read32(offset) << "\n";
            return 0;
        }

        if (command == "replace" && argc == 7) {
            const uint64_t match = elf.findUnique(argv[3], parsePattern(argv[4]));
            const uint64_t delta = parseNumber(argv[5]);
            const Pattern replacement = parsePattern(argv[6]);
            if (std::find(replacement.mask.begin(), replacement.mask.end(), 0) !=
                replacement.mask.end()) {
                throw std::runtime_error("replacement cannot contain wildcards");
            }
            elf.requireRange(match + delta, replacement.bytes.size());
            std::copy(replacement.bytes.begin(), replacement.bytes.end(),
                      elf.mutableData().begin() + match + delta);
            elf.save();
            std::cout << "0x" << std::hex << (match + delta) << "\n";
            return 0;
        }

        if (command == "assert-zero" && argc == 6) {
            const uint64_t offset = parseNumber(argv[3]);
            const uint64_t size = parseNumber(argv[4]);
            elf.requireRange(offset, size);
            const std::string domain = argv[5];
            if (domain == "exec" && !elf.isExecutableRange(offset, size)) {
                throw std::runtime_error("zero cave is not inside an executable segment");
            }
            if (domain != "exec" && domain != "load") {
                throw std::runtime_error("assert-zero domain must be exec or load");
            }
            if (!std::all_of(elf.data().begin() + offset,
                             elf.data().begin() + offset + size,
                             [](uint8_t value) { return value == 0; })) {
                throw std::runtime_error("requested cave is not zero-filled");
            }
            return 0;
        }

        if (command == "branch" && argc == 6) {
            const uint64_t from = parseNumber(argv[3]);
            const uint64_t to = parseNumber(argv[4]);
            const bool link = std::string(argv[5]) == "BL";
            if (!link && std::string(argv[5]) != "B") {
                throw std::runtime_error("branch kind must be B or BL");
            }
            if (!elf.isExecutableRange(from, 4) || !elf.isExecutableRange(to, 4)) {
                throw std::runtime_error("branch endpoints must be executable");
            }
            store32(elf.mutableData(), from,
                    encodeBranch(elf.offsetToVaddr(from), elf.offsetToVaddr(to), link));
            elf.save();
            return 0;
        }

        if (command == "inject" && argc >= 5) {
            const uint64_t cave = parseNumber(argv[3]);
            std::vector<uint8_t> payload = readFile(argv[4]);
            elf.requireRange(cave, payload.size());
            if (!elf.isExecutableRange(cave, payload.size())) {
                throw std::runtime_error("payload cave is not executable");
            }
            applyRelocations(elf, cave, payload, argc, argv, 5);
            const auto begin = elf.data().begin() + cave;
            const bool zero = std::all_of(begin, begin + payload.size(),
                                          [](uint8_t value) { return value == 0; });
            const bool same = std::equal(payload.begin(), payload.end(), begin);
            if (!zero && !same) throw std::runtime_error("payload cave is occupied");
            std::copy(payload.begin(), payload.end(), elf.mutableData().begin() + cave);
            elf.save();
            return 0;
        }

        if (command == "patch-template" && argc >= 6) {
            const uint64_t destination = parseNumber(argv[3]);
            const Pattern expected = parsePattern(argv[4]);
            if (std::find(expected.mask.begin(), expected.mask.end(), 0) !=
                expected.mask.end()) {
                throw std::runtime_error("expected bytes cannot contain wildcards");
            }
            std::vector<uint8_t> payload = readFile(argv[5]);
            if (payload.size() != expected.bytes.size()) {
                throw std::runtime_error("template and expected sizes differ");
            }
            elf.requireRange(destination, payload.size());
            if (!elf.isExecutableRange(destination, payload.size())) {
                throw std::runtime_error("template destination is not executable");
            }
            applyRelocations(elf, destination, payload, argc, argv, 6);
            const auto begin = elf.data().begin() + destination;
            const bool stock = std::equal(expected.bytes.begin(), expected.bytes.end(), begin);
            const bool same = std::equal(payload.begin(), payload.end(), begin);
            if (!stock && !same) {
                throw std::runtime_error("template destination has an unknown state");
            }
            std::copy(payload.begin(), payload.end(),
                      elf.mutableData().begin() + destination);
            elf.save();
            return 0;
        }

        usage();
        return 2;
    } catch (const std::exception& error) {
        std::cerr << "elfpatcher: " << error.what() << "\n";
        return 1;
    }
}
