#include <cstdio>
#include <fstream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>
#include "http_decoding.h"
static std::vector<uint8_t> load(const std::string& file) {
  std::ifstream in(file, std::ios::binary);
  return std::vector<uint8_t>(std::istreambuf_iterator<char>(in), {});
}
int main(int argc, char** argv) {
  if (argc != 3) return 2;
  const std::string directory = argv[1];
  std::ifstream cases(directory + "/cases.txt");
  std::ofstream audit(argv[2]);
  if (!cases || !audit) return 3;
  audit << "TraceID=native-http-codecs [请求到达] Production C++ decoder vs independent Node zlib/Brotli vectors\n";
  std::string line; int count = 0;
  while (std::getline(cases,line)) {
    std::vector<std::string> cells; std::istringstream row(line); std::string cell;
    while (std::getline(row,cell,'|')) cells.push_back(cell);
    if (cells.size()!=6) return 4;
    auto input=load(directory+"/"+cells[2]);auto expected=load(directory+"/"+cells[3]);
    std::vector<uint8_t> output;std::string error;
    bool actual=venera::DecodeHttpBody(input.data(),input.size(),cells[1],std::stoul(cells[4]),&output,&error);
    bool requested=cells[5]=="1";
    bool correct=actual==requested && (requested?output==expected:output.empty());
    audit << "TraceID=native-http-codecs [" << (correct?"PASS":"FAIL") << "] " << cells[0]
      << " input=" << input.size() << " output=" << output.size() << " reason=" << error << "\n";
    if(!correct)return 5;
    count++;
  }
  audit << "TraceID=native-http-codecs [响应返回] NATIVE_HTTP_CODEC_PASS cases=" << count << "\n";
  std::printf("NATIVE_HTTP_CODEC_PASS cases=%d\n",count);
  return count==17?0:6;
}
